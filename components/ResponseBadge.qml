import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property string responseClass: "ANSWER"
  property color foreground: OmaPilotPalette.popups.text
  property color accent: OmaPilotPalette.accent
  property string fontFamily: Style.font.family
  readonly property color tone: responseClass === "UNSURE" ? OmaPilotPalette.urgent : accent

  implicitWidth: label.implicitWidth + Style.spacing.xxl
  implicitHeight: Style.space(18)
  color: OmaPilotPalette.selectedFill(tone)
  borderSpec: Border.flat(OmaPilotPalette.normalBorder(tone), Style.normalBorderWidth)
  radius: Style.cornerRadius
  Accessible.role: Accessible.StaticText
  Accessible.name: root.responseClass

  Text {
    id: label
    anchors.centerIn: parent
    text: root.responseClass
    color: root.tone
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: Style.spaceReal(0.5)
  }
}
