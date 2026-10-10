import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/custom_text_edit.dart';

void main() {
  for (final deleteDetection in [false, true]) {
    testWidgets(
        'reset commits composition before action (sentinel=$deleteDetection)',
        (tester) async {
      final focus = FocusNode();
      final events = <String>[];
      await tester.pumpWidget(MaterialApp(
          home: CustomTextEdit(
        focusNode: focus,
        autofocus: true,
        deleteDetection: deleteDetection,
        textInputConfiguration: const TextInputConfiguration(),
        onInsert: (text) => events.add(text),
        onDelete: () {},
        onComposing: (_) {},
        onAction: (action) => events.add(action.name),
        onKeyEvent: (_, __) => KeyEventResult.ignored,
        onCommitEditingState: (value) => value,
        child: const SizedBox(),
      )));
      await tester.pump();
      final state =
          tester.state<CustomTextEditState>(find.byType(CustomTextEdit));
      final prefix = deleteDetection ? '  ' : '';
      state.updateEditingValue(TextEditingValue(
        text: '${prefix}hello',
        selection: TextSelection.collapsed(offset: prefix.length + 5),
        composing: TextRange(start: prefix.length, end: prefix.length + 5),
      ));
      expect(events, isEmpty);
      state.performAction(TextInputAction.newline);
      expect(events, ['hello', 'newline']);
      expect(state.currentTextEditingValue!.text, prefix);
      expect(state.currentTextEditingValue!.composing, TextRange.empty);
      state.resetInput();
      expect(events, ['hello', 'newline'],
          reason: 'Reset must not duplicate committed input');
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
    });
  }
}
