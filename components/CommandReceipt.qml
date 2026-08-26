import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property var receipt: null
  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  readonly property bool valid: receipt !== null && typeof receipt.command === "string"
    && receipt.command !== "" && Number(receipt.exitCode) === 0
  visible: valid
  implicitHeight: Style.space(34)
  color: Style.normalFillFor(foreground, accent)
  borderSpec: Border.controlSpec("normal", foreground, accent)
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
      color: Qt.darker(root.foreground, 1.45)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
