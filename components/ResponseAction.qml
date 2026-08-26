import QtQuick
import qs.Ui

Button {
  id: root

  property bool primary: false
  property bool quiet: false

  foreground: !root.enabled ? "#55565d" : (root.primary ? "#58d1dc" : "#a0a1a8")
  background: root.quiet ? "transparent" : (root.primary ? "#14262a" : "#15161a")
  accent: "#58d1dc"
  fontFamily: "JetBrains Mono"
  fontSize: 10
  iconSize: 12
  horizontalPadding: root.quiet ? 6 : 10
  verticalPadding: 5
  bordered: !root.quiet
  focusable: true
  radius: 0
}
