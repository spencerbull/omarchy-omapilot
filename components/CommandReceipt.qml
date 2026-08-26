import QtQuick
import QtQuick.Layouts

Item {
  id: root

  property var receipt: null
  property string fontFamily: "JetBrains Mono"
  readonly property bool valid: receipt !== null && typeof receipt.command === "string"
    && receipt.command !== "" && Number(receipt.exitCode) === 0
  visible: valid
  implicitHeight: 34
  Accessible.role: Accessible.StaticText
  Accessible.name: valid ? "Command receipt: " + receipt.command + ", exit 0" : ""

  Rectangle {
    anchors.fill: parent
    color: "#1d1d22"
    border.width: 1
    border.color: "#292a2f"
    radius: 0

    RowLayout {
      id: trace
      anchors.fill: parent
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      spacing: 9

      Text {
        text: "$"
        color: "#3fc48c"
        font.family: root.fontFamily
        font.pixelSize: 11
        font.bold: true
      }

      Text {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        text: root.valid ? root.receipt.command : ""
        color: "#d3d3d8"
        font.family: root.fontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
        maximumLineCount: 1
      }

      Text {
        text: root.valid ? "exit 0" : ""
        color: "#7c7c84"
        font.family: root.fontFamily
        font.pixelSize: 10
      }
    }
  }
}
