import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property string message: "OmaPilot could not complete that request."
  property color foreground: OmaPilotPalette.popups.text
  property color background: OmaPilotPalette.popups.background
  property color accent: OmaPilotPalette.accent
  property string fontFamily: Style.font.family
  signal detailsRequested()

  activeFocusOnTab: true
  Keys.onReturnPressed: root.detailsRequested()
  Keys.onEnterPressed: root.detailsRequested()
  Keys.onSpacePressed: root.detailsRequested()

  implicitHeight: content.implicitHeight + contentTopInset + contentBottomInset
    + Style.spacing.xl * 2
  color: OmaPilotPalette.controlFill(activeFocus, pointer.containsMouse, OmaPilotPalette.urgent)
  borderSpec: Border.flat(
    activeFocus ? OmaPilotPalette.focusBorder(OmaPilotPalette.urgent)
      : (pointer.containsMouse ? OmaPilotPalette.hoverBorder(OmaPilotPalette.urgent)
        : OmaPilotPalette.normalBorder(OmaPilotPalette.urgent)),
    activeFocus ? Style.focusBorderWidth
      : (pointer.containsMouse ? Style.hoverBorderWidth : Style.normalBorderWidth))
  radius: Style.cornerRadius
  Accessible.role: Accessible.Button
  Accessible.name: "View error details: " + message

  Behavior on color { ColorAnimation { duration: 100 } }

  RowLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: parent.contentLeftInset + Style.spacing.xl
    anchors.rightMargin: parent.contentRightInset + Style.spacing.xl
    anchors.topMargin: parent.contentTopInset + Style.spacing.xl
    spacing: Style.spacing.md

    Text {
      text: "󰅚"
      color: OmaPilotPalette.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
      Layout.alignment: Qt.AlignTop
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.xs

      Text {
        Layout.fillWidth: true
        text: root.message
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        wrapMode: Text.Wrap
      }

      Text {
        Layout.fillWidth: true
        text: "View error details"
        color: OmaPilotPalette.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Text {
      text: "󰅂"
      color: OmaPilotPalette.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
      Layout.alignment: Qt.AlignVCenter
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      root.forceActiveFocus()
      root.detailsRequested()
    }
  }
}
