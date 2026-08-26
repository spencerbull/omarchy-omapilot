import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property var receipt: null
  property color foreground: OmaPilotPalette.popups.text
  property color background: OmaPilotPalette.popups.background
  property color accent: OmaPilotPalette.accent
  property string fontFamily: Style.font.family
  readonly property bool valid: receipt !== null && typeof receipt.command === "string"
    && receipt.command !== "" && Number(receipt.exitCode) === 0
  visible: valid
  implicitHeight: Style.space(34)
  color: OmaPilotPalette.normalFill(foreground)
  borderSpec: Border.flat(OmaPilotPalette.normalBorder(foreground), Style.normalBorderWidth)
  radius: Style.cornerRadius
  Accessible.role: Accessible.StaticText
  Accessible.name: valid ? "Command receipt: " + receipt.command + ", exit 0" : ""

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: root.contentLeftInset + Style.spacing.xl
    anchors.rightMargin: root.contentRightInset + Style.spacing.xl
    spacing: Style.space(9)

    Text {
      text: "$"
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Text {
      Layout.fillWidth: true
      Layout.minimumWidth: 0
      text: root.valid ? root.receipt.command : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      maximumLineCount: 1
    }

    Text {
      text: root.valid ? "exit 0" : ""
      color: OmaPilotPalette.darkForeground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
