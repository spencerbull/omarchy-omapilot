import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Protocol.js" as Protocol

Item {
  id: root

  required property var backend
  property var details: null
  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  readonly property var normalized: Protocol.normalizedError(details,
    backend ? backend.statusMessage : "OmaPilot could not complete that request.")

  signal dismissed()
  signal authenticationRequested()

  implicitHeight: content.implicitHeight

  function forceInitialFocus() {
    backButton.forceActiveFocus()
  }

  ColumnLayout {
    id: content
    anchors.fill: parent
    spacing: Style.spacing.xxl

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md

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
          color: Qt.darker(root.foreground, 1.45)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    BorderSurface {
      Layout.fillWidth: true
      Layout.fillHeight: true
      implicitHeight: detailsContent.implicitHeight + contentTopInset + contentBottomInset
        + Style.spacing.xxl * 2
      color: Style.normalFillFor(Color.urgent, Color.urgent)
      borderSpec: Border.controlSpec("normal", Color.urgent, Color.urgent)
      radius: Style.cornerRadius
      clip: true

      Flickable {
        id: detailsScroll
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: parent.contentLeftInset + Style.spacing.xxl
        anchors.rightMargin: parent.contentRightInset + Style.spacing.xxl
        anchors.topMargin: parent.contentTopInset + Style.spacing.xxl
        anchors.bottomMargin: parent.contentBottomInset + Style.spacing.xxl
        contentWidth: width
        contentHeight: detailsContent.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        clip: true

        ColumnLayout {
          id: detailsContent
          width: detailsScroll.width
          spacing: Style.spacing.lg

          Text {
            Layout.fillWidth: true
            text: root.normalized.title
            color: Color.urgent
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

          PanelSeparator {
            Layout.fillWidth: true
            foreground: root.foreground
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.lg

            Text {
              text: "Code"
              color: Qt.darker(root.foreground, 1.45)
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
              color: Qt.darker(root.foreground, 1.45)
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

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.md

            Button {
              iconText: "󰆏"
              text: "Copy details"
              foreground: root.foreground
              background: root.background
              bordered: true
              focusable: true
              onClicked: root.backend.copyText(Protocol.errorDiagnosticText(root.normalized))
            }

            Item { Layout.fillWidth: true }

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
