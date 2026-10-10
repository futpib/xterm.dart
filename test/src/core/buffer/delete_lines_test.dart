import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void expectOwnedLines(Terminal terminal) {
  final lines = terminal.buffer.lines;
  for (var i = 0; i < lines.length; i++) {
    expect(lines[i].attached, isTrue, reason: 'row $i');
    expect(lines[i].index, i);
  }
}

void main() {
  for (final chunkSize in [1, 7, 1000]) {
    test('delete then scroll accepts terminal output in chunks of $chunkSize',
        () {
      final terminal = Terminal(maxLines: 100)..resize(20, 5);
      // tmux emits DL when redrawing Codex's inline history. The following
      // line feed used to throw in IndexedItem._move on a detached line.
      const output = '\x1b[?1049h'
          'one\r\ntwo\r\nthree\r\nfour\r\nfive'
          '\x1b[H\x1b[M\x1b[5;1H\n';
      for (var i = 0; i < output.length; i += chunkSize) {
        terminal.write(
            output.substring(i, (i + chunkSize).clamp(0, output.length)));
      }
      expect(terminal.buffer.lines.toList().map((line) => line.toString()),
          ['three', 'four', 'five', '', '']);
      expectOwnedLines(terminal);
    });
  }

  for (final history in [false, true]) {
    for (final count in [0, 1, 2, 3, 99]) {
      test(
          'delete $count lines preserves anchors and margins, history=$history',
          () {
        final terminal = Terminal(maxLines: 40)..resize(20, 6);
        if (history) {
          for (var i = 0; i < 80; i++) {
            terminal.write('history $i\r\n');
          }
        }
        final buffer = terminal.buffer;
        buffer.setVerticalMargins(1, 4);
        buffer.setCursor(3, 2);
        final start = buffer.absoluteCursorY;
        final bottom = buffer.absoluteMarginBottom;
        final before = buffer.lines.toList();
        final anchors = [
          for (var i = 0; i < before.length; i++) buffer.createAnchor(2, i)
        ];
        final n = count.clamp(0, bottom - start + 1);
        buffer.deleteLines(count);
        expect(buffer.lines.length, before.length);
        expectOwnedLines(terminal);
        for (var i = 0; i < before.length; i++) {
          if (i < start || i > bottom) {
            expect(buffer.lines[i], same(before[i]));
            expect(anchors[i].offset, CellOffset(2, i));
          } else if (i < start + n) {
            expect(anchors[i].attached, isFalse);
          } else {
            expect(buffer.lines[i - n], same(before[i]));
            expect(anchors[i].offset, CellOffset(2, i - n));
          }
        }
        for (var i = bottom - n + 1; i <= bottom; i++) {
          expect(buffer.lines[i].toString(), isEmpty);
        }
        buffer.scrollUp(1);
        buffer.scrollDown(1);
        expectOwnedLines(terminal);
        for (final anchor in anchors) {
          anchor.dispose();
        }
      });
    }
  }

  test('delete outside margins leaves content and anchors unchanged', () {
    final terminal = Terminal()..resize(20, 6);
    terminal.write('one\r\ntwo\r\nthree\r\nfour\r\nfive\r\nsix');
    final buffer = terminal.buffer;
    buffer.setVerticalMargins(1, 4);
    final before = buffer.lines.toList();
    for (final y in [0, 5]) {
      buffer.setCursor(2, y);
      buffer.deleteLines(99);
      expect(buffer.lines.toList(), orderedEquals(before));
      expect(buffer.cursorX, 2);
      expectOwnedLines(terminal);
    }
  });

  test('tmux-style deletes and scrolling survive repeated height changes', () {
    final terminal = Terminal()..resize(48, 49);
    terminal.write('\x1b[?1049h');
    for (var pass = 0; pass < 40; pass++) {
      final height = pass.isEven ? 53 : 49;
      terminal.resize(48, height);
      terminal.write('\x1b[2;${height - 1}r\x1b[2;1H'
          'table $pass\r\nnext line\r\nlast line'
          '\x1b[2;1H\x1b[M\x1b[${height - 1};1H\n');
      expect(terminal.buffer.lines.length, height);
      expectOwnedLines(terminal);
    }
    terminal.write('\x1b[r\x1b[Hhello world');
    final controller = TerminalController();
    controller.setSelection(
        terminal.buffer.createAnchor(0, 0), terminal.buffer.createAnchor(5, 0));
    expect(terminal.buffer.getText(controller.selection!), 'hello');
    controller.dispose();
  });
}
