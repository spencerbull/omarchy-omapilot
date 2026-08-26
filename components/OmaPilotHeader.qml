import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Presentation.js" as Presentation
import "Protocol.js" as Protocol

Item {
  id: root

  required property var backend
  property bool dangerousAutoApprove: false
  property bool motionEnabled: true
  property color foreground: OmaPilotPalette.popups.text
  property color background: OmaPilotPalette.popups.background
  property color accent: OmaPilotPalette.accent
  property string fontFamily: Style.font.family

  signal settingsRequested()

  implicitHeight: headerContent.implicitHeight

  ColumnLayout {
    id: headerContent
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.spacing.md

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.lg

      OmaPilotMark {
        size: Style.space(42)
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        active: root.backend && root.backend.busy
        motionEnabled: root.motionEnabled
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Text {
          text: "OmaPilot"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Text {
          Layout.fillWidth: true
          text: "Ready to help with this desktop"
          color: OmaPilotPalette.darkForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: "󰒓"
        tooltipText: "OmaPilot settings"
        foreground: root.foreground
        size: Style.space(34)
        bordered: true
        focusable: true
        Accessible.name: tooltipText
        onClicked: root.settingsRequested()
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md

      Text {
        Layout.fillWidth: true
        text: root.backend
          ? Protocol.providerLabel(root.backend.provider)
            + (root.backend.model ? " · " + root.backend.model : "")
          : ""
        color: OmaPilotPalette.darkForeground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        Accessible.role: Accessible.StaticText
        Accessible.name: text
      }

      Text {
        text: "\uebc1  " + Presentation.permissionNotice(root.dangerousAutoApprove)
        color: root.dangerousAutoApprove
          ? OmaPilotPalette.urgent : OmaPilotPalette.darkForeground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        Accessible.role: Accessible.StaticText
        Accessible.name: Presentation.permissionNotice(root.dangerousAutoApprove)
      }
    }
  }
}
