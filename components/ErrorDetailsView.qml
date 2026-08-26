import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Protocol.js" as Protocol

Item {
  id: root

  required property var backend
  property var details: null
  property color foreground: OmaPilotPalette.popups.text
  property color background: OmaPilotPalette.popups.background
  property color accent: OmaPilotPalette.accent
  property string fontFamily: Style.font.family
  readonly property var normalized: Protocol.normalizedError(details,
    backend ? backend.statusMessage : "OmaPilot could not complete that request.")

  signal dismissed()
  signal authenticationRequested()

  implicitHeight: Style.space(360)

  function forceInitialFocus() {
    backButton.forceActiveFocus()
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(56)
      Layout.leftMargin: Style.spacing.panelPadding
      Layout.rightMargin: Style.spacing.panelPadding
      spacing: Style.space(9)

      PanelActionButton {
        id: backButton
        iconText: "󰁍"
        tooltipText: "Back to conversation"
        foreground: root.foreground
        focusable: true
        Accessible.name: tooltipText
        onClicked: root.dismissed()
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Text {
          text: "Error details"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Text {
          text: "What OmaPilot received from the current harness"
          color: OmaPilotPalette.darkForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.spacing.hairline
      color: OmaPilotPalette.normalBorder(root.foreground)
      Accessible.ignored: true
    }

    Flickable {
      id: detailsScroll
      Layout.fillWidth: true
      Layout.fillHeight: true
      contentWidth: width
      contentHeight: detailsCard.implicitHeight + Style.spacing.panelPadding * 2
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      clip: true

      BorderSurface {
        id: detailsCard
        x: Style.spacing.panelPadding
        y: Style.spacing.panelPadding
        width: Math.max(0, detailsScroll.width - Style.spacing.panelPadding * 2)
        implicitHeight: detailsContent.implicitHeight + contentTopInset + contentBottomInset
        padding: Style.spacing.xxl
        color: OmaPilotPalette.normalFill(OmaPilotPalette.urgent)
        borderSpec: Border.flat(
          OmaPilotPalette.normalBorder(OmaPilotPalette.urgent), Style.normalBorderWidth)
        radius: Style.cornerRadius
        clip: true

        ColumnLayout {
          id: detailsContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.leftMargin: parent.contentLeftInset
          anchors.rightMargin: parent.contentRightInset
          anchors.topMargin: parent.contentTopInset
          spacing: Style.spacing.lg

          Text {
            Layout.fillWidth: true
            text: root.normalized.title
            color: OmaPilotPalette.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            wrapMode: Text.Wrap
          }

          TextEdit {
            Layout.fillWidth: true
            text: root.normalized.message
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            readOnly: true
            selectByMouse: true
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.spacing.hairline
            color: OmaPilotPalette.normalBorder(root.foreground)
            Accessible.ignored: true
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.lg

            Text {
              text: "Code"
              color: OmaPilotPalette.darkForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            TextEdit {
              Layout.fillWidth: true
              text: root.normalized.code
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: TextEdit.WrapAnywhere
              textFormat: Text.PlainText
              readOnly: true
              selectByMouse: true
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.lg

            Text {
              text: "Retryable"
              color: OmaPilotPalette.darkForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              Layout.fillWidth: true
              text: root.normalized.retryable ? "Yes" : "No"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            spacing: Style.spacing.md

            Button {
              iconText: "󰆏"
              text: "Copy details"
              iconSize: fontSize
              foreground: root.foreground
              background: root.background
              bordered: true
              focusable: true
              onClicked: root.backend.copyText(Protocol.errorDiagnosticText(root.normalized))
            }

            Button {
              visible: root.backend && root.backend.provider === "builtin"
                && root.backend.providers.length === 0
              text: "Open authentication"
              foreground: root.foreground
              background: root.background
              accent: root.accent
              active: true
              bordered: true
              focusable: true
              onClicked: root.authenticationRequested()
            }

            Button {
              visible: root.backend && root.backend.canRetry
              text: "Restart OmaPilot"
              foreground: root.foreground
              background: root.background
              accent: root.accent
              active: true
              bordered: true
              focusable: true
              onClicked: {
                root.backend.retryBroker()
                root.dismissed()
              }
            }
          }
        }
      }
    }
  }
}
