import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/src/core/buffer/buffer.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/src/ui/selection_mode.dart';

/// Mobile selection UI. Buffer anchors remain the source of truth; no terminal
/// text is copied into an editable field (which could send edits to the shell).
class TerminalSelectionOverlay {
  TerminalSelectionOverlay({
    required this.context,
    required this.terminal,
    required this.controller,
    required this.renderTerminal,
    required this.scrollController,
    required this.readOnly,
    required this.onPaste,
  }) {
    controller.addListener(update);
    terminal.addListener(update);
  }

  final BuildContext context;
  final Terminal terminal;
  final TerminalController controller;
  final RenderTerminal Function() renderTerminal;
  final ScrollController scrollController;
  final bool readOnly;
  final VoidCallback onPaste;
  OverlayEntry? _entry;
  Buffer? _buffer;
  bool _disposed = false;
  bool _scheduled = false;
  bool _dragging = false;
  Offset? _dragPosition;
  bool _dragStartHandle = false;
  Timer? _autoScroll;

  void show() {
    final platform = Theme.of(context).platform;
    if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
      return;
    }
    if (controller.selection == null || _disposed) return;
    _buffer = terminal.buffer;
    if (_entry == null) {
      _entry = OverlayEntry(builder: _build);
      Overlay.of(context).insert(_entry!);
    }
    update();
  }

  void hide() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _dragging = false;
    _dragPosition = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void dispose() {
    _disposed = true;
    controller.removeListener(update);
    terminal.removeListener(update);
    hide();
  }

  /// Called after terminal layout/paint too, so output, reflow and scrolling
  /// move the controls even when the selection anchors did not notify.
  void update() {
    if (_disposed || _entry == null || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed || _entry == null) return;
      if (controller.selection == null || terminal.buffer != _buffer) {
        if (terminal.buffer != _buffer) controller.clearSelection();
        hide();
        return;
      }
      _entry?.markNeedsBuild();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget _build(BuildContext overlayContext) {
    final selection = controller.selection?.normalized;
    final render = renderTerminal();
    if (selection == null || !render.attached || terminal.buffer != _buffer) {
      return const SizedBox.shrink();
    }
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    Offset position(CellOffset cell) => overlay.globalToLocal(
          render.localToGlobal(render.getOffset(cell)),
        );
    final topLeft = overlay.globalToLocal(render.localToGlobal(Offset.zero));
    final viewport = topLeft & render.size;
    final height = render.lineHeight;
    final start = position(selection.begin) + Offset(0, height);
    final end = position(selection.end) + Offset(0, height);
    bool visible(Offset point) =>
        point.dy > viewport.top &&
        point.dy <= viewport.bottom &&
        point.dx >= viewport.left &&
        point.dx <= viewport.right;
    final controls = Theme.of(context).platform == TargetPlatform.iOS
        ? cupertinoTextSelectionControls
        : materialTextSelectionControls;
    final startVisible = visible(start);
    final endVisible = visible(end);
    final selectedVisible =
        end.dy > viewport.top && start.dy - height < viewport.bottom;
    final middleX = selection.begin.y == selection.end.y
        ? (start.dx + end.dx) / 2
        : viewport.center.dx;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (startVisible || _dragging) _handle(controls, start, height, true),
        if (endVisible || _dragging) _handle(controls, end, height, false),
        if (!_dragging && selectedVisible)
          AdaptiveTextSelectionToolbar.buttonItems(
            anchors: TextSelectionToolbarAnchors(
              primaryAnchor: Offset(middleX,
                  (start.dy - height).clamp(viewport.top, viewport.bottom)),
              secondaryAnchor:
                  Offset(middleX, end.dy.clamp(viewport.top, viewport.bottom)),
            ),
            buttonItems: [
              ContextMenuButtonItem(
                type: ContextMenuButtonType.copy,
                onPressed: _copy,
              ),
              if (!readOnly)
                ContextMenuButtonItem(
                  type: ContextMenuButtonType.paste,
                  onPressed: _paste,
                ),
              ContextMenuButtonItem(
                type: ContextMenuButtonType.selectAll,
                onPressed: _selectAll,
              ),
            ],
          ),
      ],
    );
  }

  Widget _handle(
      TextSelectionControls controls, Offset point, double height, bool start) {
    var type =
        start ? TextSelectionHandleType.left : TextSelectionHandleType.right;
    final size = controls.getHandleSize(height);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    // Turn edge handles inward so their platform shape stays reachable.
    if (start && point.dx < size.width) type = TextSelectionHandleType.right;
    if (!start && point.dx > overlay.size.width - size.width) {
      type = TextSelectionHandleType.left;
    }
    final anchor = controls.getHandleAnchor(type, height);
    // Keep the platform shape, with at least a 48px touch target.
    final width = size.width < 48 ? 48.0 : size.width;
    final targetHeight = size.height < 48 ? 48.0 : size.height;
    final padding =
        Offset((width - size.width) / 2, (targetHeight - size.height) / 2);
    final left = (point.dx - anchor.dx - padding.dx)
        .clamp(0.0, (overlay.size.width - width).clamp(0.0, double.infinity));
    final top = point.dy - anchor.dy - padding.dy;
    return Positioned(
      key: ValueKey(start ? 'terminal-start-overlay' : 'terminal-end-overlay'),
      left: left,
      top: top,
      child: Semantics(
        label: start ? 'Start of selection' : 'End of selection',
        child: GestureDetector(
          key: ValueKey(
              start ? 'terminal-selection-start' : 'terminal-selection-end'),
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            if (_dragging) return;
            _dragging = true;
            _dragStartHandle = start;
            final selection = controller.selection!.normalized;
            _dragPosition = renderTerminal().localToGlobal(
              renderTerminal()
                      .getOffset(start ? selection.begin : selection.end) +
                  Offset(0, height / 2),
            );
            _autoScroll = Timer.periodic(const Duration(milliseconds: 50), (_) {
              if (_dragPosition != null) _moveHandle();
            });
            update();
          },
          onPanUpdate: (details) {
            if (!_dragging || _dragStartHandle != start) return;
            _dragPosition = _dragPosition! + details.delta;
            _moveHandle();
          },
          onPanEnd: (_) {
            if (_dragStartHandle == start) _endDrag();
          },
          onPanCancel: () {
            if (_dragStartHandle == start) _endDrag();
          },
          child: SizedBox(
            width: width,
            height: targetHeight,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: point.dx - anchor.dx - left,
                top: padding.dy,
                child: controls.buildHandle(context, type, height),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _endDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _dragging = false;
    _dragPosition = null;
    update();
  }

  void _moveHandle() {
    final selection = controller.selection?.normalized;
    if (selection == null || terminal.buffer != _buffer) return;
    final render = renderTerminal();
    var local = render.globalToLocal(_dragPosition!);
    if (scrollController.hasClients) {
      final edge = render.lineHeight;
      final delta = local.dy < edge
          ? -edge
          : local.dy > render.size.height - edge
              ? edge
              : 0.0;
      if (delta != 0) {
        final position = scrollController.position;
        scrollController.jumpTo((position.pixels + delta)
            .clamp(position.minScrollExtent, position.maxScrollExtent));
      }
    }
    local = Offset(local.dx, local.dy.clamp(0.0, render.size.height - 1));
    final row = render.getCellOffset(local).y;
    final origin = render.getOffset(CellOffset(0, row));
    var column = ((local.dx - origin.dx) / render.cellSize.width)
        .round()
        .clamp(0, terminal.viewWidth);
    // Never split the trailing cell of a wide character.
    final line = terminal.buffer.lines[row];
    if (column > 0 &&
        column < line.length &&
        line.getWidth(column) == 0 &&
        line.getWidth(column - 1) == 2) {
      column += _dragStartHandle ? -1 : 1;
    }
    final cell = CellOffset(column, row);
    final begin = _dragStartHandle ? cell : selection.begin;
    final end = _dragStartHandle ? selection.end : cell;
    if (!begin.isBefore(end)) return;
    controller.setSelection(
      terminal.buffer.createAnchorFromOffset(begin),
      terminal.buffer.createAnchorFromOffset(end),
      mode: SelectionMode.line,
    );
  }

  Future<void> _copy() async {
    final selection = controller.selection;
    if (selection == null) return;
    final entry = _entry;
    await Clipboard.setData(
        ClipboardData(text: terminal.buffer.getText(selection)));
    if (!_disposed && entry == _entry) {
      controller.clearSelection();
      hide();
    }
  }

  Future<void> _paste() async {
    if (readOnly) return;
    final entry = _entry;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (_disposed || entry != _entry || data?.text == null) return;
    terminal.paste(data!.text!);
    controller.clearSelection();
    hide();
    onPaste();
  }

  void _selectAll() {
    controller.setSelection(
      terminal.buffer.createAnchor(0, 0),
      terminal.buffer
          .createAnchor(terminal.viewWidth, terminal.buffer.height - 1),
      mode: SelectionMode.line,
    );
  }
}
