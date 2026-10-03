import 'package:test/test.dart';
import 'package:xterm/core.dart';

void main() {
  // XTerm Control Sequences, "Wheel mice" and "Extended coordinates":
  // https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
  // Wheel buttons occupy codes 64..67. The value 4 is the Shift modifier, not
  // part of the wheel button number.
  const buttons = {
    TerminalMouseButton.wheelUp: 64,
    TerminalMouseButton.wheelDown: 65,
    TerminalMouseButton.wheelLeft: 66,
    TerminalMouseButton.wheelRight: 67,
  };
  const encodings = {
    'normal': '',
    'utf': '\x1b[?1005h',
    'sgr': '\x1b[?1006h',
    'urxvt': '\x1b[?1015h',
  };

  for (final encoding in encodings.entries) {
    for (final button in buttons.entries) {
      test('${encoding.key} ${button.key.name} has no Shift modifier', () {
        final output = <String>[];
        final terminal = Terminal(onOutput: output.add);
        terminal.write('\x1b[?1000h${encoding.value}');

        expect(
          terminal.mouseInput(
            button.key,
            TerminalMouseButtonState.down,
            const CellOffset(18, 15),
          ),
          isTrue,
        );
        final packet = output.single;
        if (encoding.key == 'sgr') {
          expect(packet, '\x1b[<${button.value};19;16M');
        } else if (encoding.key == 'urxvt') {
          expect(packet, '\x1b[${button.value + 32};19;16M');
        } else {
          expect(packet, startsWith('\x1b[M'));
          expect(packet.codeUnitAt(3), button.value + 32);
        }

        output.clear();
        expect(
          terminal.mouseInput(
            button.key,
            TerminalMouseButtonState.up,
            const CellOffset(18, 15),
          ),
          isFalse,
        );
        expect(output, isEmpty, reason: 'Wheel releases are not reported');
      });
    }
  }
}
