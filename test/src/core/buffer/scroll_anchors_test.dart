import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  for (final down in [false, true]) {
    for (final full in [false, true]) {
      for (final count in [0, 1, 2, 4, 99]) {
        test(
            'scroll ${down ? 'down' : 'up'} $count preserves anchors '
            'with circular storage ${full ? 'wrapped' : 'unwrapped'}', () {
          final terminal = Terminal(maxLines: 40);
          terminal.resize(20, 6);
          if (full) {
            for (var i = 0; i < 80; i++) {
              terminal.write('history $i\r\n');
            }
          }
          final buffer = terminal.buffer;
          buffer.setVerticalMargins(1, 4);
          final top = buffer.absoluteMarginTop;
          final bottom = buffer.absoluteMarginBottom;
          final before = [
            for (var i = 0; i < buffer.lines.length; i++) buffer.lines[i]
          ];
          final anchors = [
            for (var i = 0; i < buffer.lines.length; i++)
              buffer.createAnchor(2, i)
          ];
          final n = count.clamp(0, 4);
          if (down) {
            buffer.scrollDown(count);
          } else {
            buffer.scrollUp(count);
          }
          expect(buffer.lines.length, before.length);
          for (var i = 0; i < before.length; i++) {
            expect(buffer.lines[i].attached, isTrue, reason: 'row $i');
            expect(buffer.lines[i].index, i);
            if (i < top || i > bottom) {
              expect(buffer.lines[i], same(before[i]));
              expect(anchors[i].offset, CellOffset(2, i));
              continue;
            }
            final dropped = down ? i > bottom - n : i < top + n;
            if (dropped) {
              expect(anchors[i].attached, isFalse);
            } else {
              final target = i + (down ? n : -n);
              expect(anchors[i].offset, CellOffset(2, target));
              expect(buffer.lines[target], same(before[i]));
            }
          }
          // Scrolling again and then inserting lines used to assert on a
          // detached line; verify the buffer remains usable after the move.
          buffer.scrollUp(1);
          buffer.scrollDown(1);
          buffer.setCursor(0, 1);
          terminal.write('\x1b[Lnew text');
          for (var i = 0; i < buffer.lines.length; i++) {
            expect(buffer.lines[i].attached, isTrue);
            expect(buffer.lines[i].index, i);
          }
          for (final anchor in anchors) {
            anchor.dispose();
          }
        });
      }
    }
  }

  test('text shifted in the alternate screen can still be selected', () {
    final terminal = Terminal();
    terminal.resize(20, 6);
    terminal.write('\x1b[?1049hfirst\r\nhello world\r\nlast');
    terminal.buffer.scrollUp(1);
    final controller = TerminalController();
    controller.setSelection(
        terminal.buffer.createAnchor(0, 0), terminal.buffer.createAnchor(5, 0));
    expect(controller.selection, isNotNull);
    expect(terminal.buffer.getText(controller.selection!), 'hello');
    controller.clearSelection();
    controller.dispose();
  });
}
