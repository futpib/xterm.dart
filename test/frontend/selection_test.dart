import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  late Terminal terminal;
  late TerminalController controller;
  late GlobalKey<TerminalViewState> key;
  String? clipboard;
  final output = <String>[];

  setUp(() {
    terminal = Terminal(onOutput: output.add);
    controller = TerminalController();
    key = GlobalKey<TerminalViewState>();
    clipboard = null;
    output.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      if (call.method == 'Clipboard.getData') return {'text': clipboard};
      return null;
    });
  });

  Future<void> mount(WidgetTester tester,
      {bool readOnly = false,
      TargetPlatform platform = TargetPlatform.android,
      ScrollController? scroll,
      Size size = const Size(600, 300)}) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
          body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: TerminalView(terminal,
              key: key,
              controller: controller,
              readOnly: readOnly,
              scrollController: scroll),
        ),
      )),
    ));
    terminal.write('hello world\r\nsecond line');
    await tester.pumpAndSettle();
  }

  Offset cell(int x, int y) {
    final render = key.currentState!.renderTerminal;
    return render.localToGlobal(render.getOffset(CellOffset(x, y)) +
        Offset(render.cellSize.width / 2, render.lineHeight / 2));
  }

  Future<void> select(WidgetTester tester) async {
    await tester.longPressAt(cell(2, 0));
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('long press shows handles and copies on $platform',
        (tester) async {
      await mount(tester, platform: platform);
      await select(tester);
      expect(terminal.buffer.getText(controller.selection!), 'hello');
      expect(find.byKey(const ValueKey('terminal-selection-start')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('terminal-selection-end')), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(clipboard, 'hello');
      expect(controller.selection, isNull);
      expect(find.text('Copy'), findsNothing);
      expect(output, isEmpty);
    });
  }

  testWidgets('double tap, adjust end, copy exact range', (tester) async {
    await mount(tester);
    await tester.tapAt(cell(2, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(cell(2, 0));
    await tester.pumpAndSettle();
    final handle = find.byKey(const ValueKey('terminal-selection-end'));
    expect(handle, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    final width = key.currentState!.renderTerminal.cellSize.width;
    // First movement crosses drag slop; subsequent movement adjusts cells.
    await gesture.moveBy(const Offset(25, 0));
    await tester.pump();
    await gesture.moveBy(Offset(width * 3, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.selection!.end.x, greaterThan(5));
    final selected = terminal.buffer.getText(controller.selection!);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(clipboard, selected);
  });

  testWidgets('Paste uses bracketed paste and clears selection',
      (tester) async {
    await mount(tester);
    terminal.write('\x1b[?2004h');
    clipboard = 'echo hello\n';
    await select(tester);
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(output.join(), '\x1b[200~echo hello\n\x1b[201~');
    expect(controller.selection, isNull);
  });

  testWidgets('read only menu omits Paste', (tester) async {
    await mount(tester, readOnly: true);
    await select(tester);
    expect(find.text('Paste'), findsNothing);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('Select All includes scrollback and copy preserves wrapped text',
      (tester) async {
    final scroll = ScrollController();
    await mount(tester, scroll: scroll, size: const Size(200, 100));
    terminal.write('\r\n${'word ' * 100}');
    await tester.pumpAndSettle();
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    await select(tester);
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(controller.selection!.begin, const CellOffset(0, 0));
    expect(controller.selection!.end.y, terminal.buffer.height - 1);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(clipboard, startsWith('hello world\nsecond line\nword word'));
    expect(clipboard, contains('word ' * 90));
  });

  testWidgets('tap dismisses controls; disposal cancels pending gesture timer',
      (tester) async {
    await mount(tester);
    await select(tester);
    await tester.tapAt(cell(30, 15));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
    await select(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('buffer switch dismisses stale controls', (tester) async {
    await mount(tester);
    await select(tester);
    terminal.write('\x1b[?1049h');
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('mouse double click does not show touch handles', (tester) async {
    await mount(tester);
    await tester.tapAt(cell(2, 0), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(cell(2, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(controller.selection, isNotNull);
    expect(find.text('Copy'), findsNothing);
  });
  testWidgets('start handle adjusts independently and cannot cross end',
      (tester) async {
    await mount(tester);
    await select(tester);
    final handle = find.byKey(const ValueKey('terminal-selection-start'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(25, 0));
    await tester.pump();
    await gesture
        .moveBy(Offset(key.currentState!.renderTerminal.cellSize.width * 2, 0));
    await tester.pump();
    expect(controller.selection!.begin.x, greaterThan(0));
    expect(controller.selection!.end.x, 5);
    final before = controller.selection!;
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();
    expect(controller.selection, before);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('scrolling moves handles and hides offscreen controls',
      (tester) async {
    final scroll = ScrollController();
    await mount(tester, scroll: scroll);
    for (var i = 0; i < 40; i++) {
      terminal.write('\r\nline $i');
    }
    await tester.pumpAndSettle();
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.longPressAt(cell(2, 4));
    await tester.pumpAndSettle();
    final handle = find.byKey(const ValueKey('terminal-selection-start'));
    final before = tester.getCenter(handle);
    scroll.jumpTo(key.currentState!.renderTerminal.lineHeight * 2);
    await tester.pumpAndSettle();
    expect(tester.getCenter(handle).dy, lessThan(before.dy));
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(handle, findsNothing);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('handle held at viewport edge scrolls through scrollback',
      (tester) async {
    final scroll = ScrollController();
    await mount(tester, scroll: scroll);
    for (var i = 0; i < 50; i++) {
      terminal.write('\r\nline $i');
    }
    await tester.pumpAndSettle();
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.longPressAt(cell(2, 4));
    await tester.pumpAndSettle();
    final handle = find.byKey(const ValueKey('terminal-selection-end'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 350));
    await tester.pump(const Duration(milliseconds: 300));
    expect(scroll.offset, greaterThan(0));
    expect(controller.selection!.end.y, greaterThan(4));
    await gesture.up();
    await tester.pumpAndSettle();
    final stopped = scroll.offset;
    await tester.pump(const Duration(milliseconds: 300));
    expect(scroll.offset, stopped);
  });

  testWidgets('focus loss removes controls', (tester) async {
    await mount(tester);
    await select(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
  });
  testWidgets('viewport shrink does not scroll an active selection out of view',
      (tester) async {
    final scroll = ScrollController();
    Widget app(double height, bool resize) => MaterialApp(
          home: Scaffold(
              body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
                width: 600,
                height: height,
                child: TerminalView(terminal,
                    key: key,
                    controller: controller,
                    scrollController: scroll,
                    autoResize: resize)),
          )),
        );
    await tester.pumpWidget(app(300, true));
    terminal.write('hello world');
    await tester.pumpAndSettle();
    await select(tester);
    await tester.pumpWidget(app(100, false));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(find.text('Copy'), findsOneWidget);
    expect(terminal.buffer.getText(controller.selection!), 'hello');
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0,
        reason: 'Copy must not restore stale stick-to-bottom');
  });

  testWidgets('viewport shrink keeps a bottom selection above the keyboard',
      (tester) async {
    final scroll = ScrollController();
    Widget app(double height, bool resize) => MaterialApp(
          home: Scaffold(
              body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
                width: 600,
                height: height,
                child: TerminalView(terminal,
                    key: key,
                    controller: controller,
                    scrollController: scroll,
                    autoResize: resize)),
          )),
        );
    await tester.pumpWidget(app(300, true));
    final row = terminal.viewHeight - 2;
    terminal.write('\r\n' * row + 'hello world');
    await tester.pumpAndSettle();
    await tester.longPressAt(cell(2, row));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(100, false));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    final render = key.currentState!.renderTerminal;
    final top = render.getOffset(CellOffset(0, row)).dy;
    expect(top, greaterThanOrEqualTo(0));
    expect(top + render.lineHeight, lessThanOrEqualTo(100.01));
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(clipboard, 'hello');
  });
}
