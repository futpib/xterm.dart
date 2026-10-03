enum TerminalMouseButton {
  left(id: 0),

  middle(id: 1),

  right(id: 2),

  wheelUp(id: 64, isWheel: true),

  wheelDown(id: 65, isWheel: true),

  wheelLeft(id: 66, isWheel: true),

  wheelRight(id: 67, isWheel: true),
  ;

  /// The id that is used to report a button press or release to the terminal.
  ///
  /// Wheel buttons use the low two bits (0..3) plus 64. Physical button
  /// numbers 4..7 must not be added to 64: the value 4 is the Shift modifier.
  /// See "Wheel mice" in the XTerm Control Sequences documentation:
  /// https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
  final int id;

  /// Whether this button is a mouse wheel button.
  final bool isWheel;

  const TerminalMouseButton({required this.id, this.isWheel = false});
}
