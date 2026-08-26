import QtQuick
import qs.Commons
import qs.Ui

Button {
  id: root

  property bool primary: false
  property bool quiet: false

  foreground: root.enabled
    ? (root.primary ? Color.accent : Color.popups.text)
    : Qt.darker(Color.popups.text, 1.55)
  background: "transparent"
  accent: Color.accent
  fontFamily: Style.font.family
  fontSize: Style.font.caption
  iconSize: Style.font.body
  horizontalPadding: root.quiet ? Style.spacing.md : Style.spacing.controlPaddingX
  verticalPadding: Style.space(5)
  active: root.primary
  bordered: !root.quiet
  focusable: true
}
