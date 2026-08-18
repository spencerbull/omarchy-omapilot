import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Protocol.js" as Protocol

Item {
  id: root

  required property var backend
  property bool dangerousAutoApprove: false
  property var quickActions: []
  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  readonly property var modeProviders: Protocol.harnessOptions()
  readonly property var browserCompanion: backend && backend.browserCompanionStatus
    ? backend.browserCompanionStatus : ({
      phase: "ready", relayInstalled: false, setupAvailable: false,
      chromiumConnected: false, firefoxConnected: false,
      chromiumExtensionPath: "", firefoxExtensionPath: "", message: ""
    })
  readonly property bool browserCompanionConnected: backend ? backend.browserCompanionConnected === true : false
  readonly property bool browserCompanionBusy: backend ? backend.browserCompanionBusy === true : false
  property bool browserRemoveConfirmation: false
  property bool browserSetupExpanded: false
  readonly property bool popupOpen: providerPicker.popupOpen || modelPicker.popupOpen

  signal dangerousAutoApproveRequested(bool enabled)
  signal providerChanged(string provider)
  signal modelChanged(string provider, string model)
  signal quickActionsEdited(var actions)
  signal browserCompanionInstallRequested()
  signal browserCompanionUninstallRequested()
  signal browserCompanionRefreshRequested()
  signal browserCompanionOpenSettingsRequested(string family)
  signal browserCompanionCopyPathRequested(string family)
  signal recentChatsRequested()
  signal dismissed()

  implicitHeight: settingsContent.implicitHeight

  function closePopups(restoreFocus) {
    providerPicker.close()
    modelPicker.close()
    if (restoreFocus !== false)
      Qt.callLater(function() { backButton.forceActiveFocus() })
  }

  function forceInitialFocus() {
    backButton.forceActiveFocus()
  }

  Flickable {
    id: settingsScroll
    anchors.fill: parent
    contentWidth: width
    contentHeight: settingsContent.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    ColumnLayout {
      id: settingsContent
      width: settingsScroll.width
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
            text: "OmaPilot settings"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Text {
            text: "Harness, browser context, permissions, and quick actions"
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      BorderSurface {
        Layout.fillWidth: true
        implicitHeight: settingsFields.implicitHeight + contentTopInset + contentBottomInset + Style.spacing.xxl * 2
        color: Style.normalFillFor(root.foreground, root.accent)
        borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
        radius: Style.cornerRadius

        ColumnLayout {
          id: settingsFields
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.leftMargin: parent.contentLeftInset + Style.spacing.xxl
          anchors.rightMargin: parent.contentRightInset + Style.spacing.xxl
          anchors.topMargin: parent.contentTopInset + Style.spacing.xxl
          spacing: Style.spacing.lg

          Text {
            Layout.fillWidth: true
            text: "Permissions"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            Layout.fillWidth: true
            text: root.dangerousAutoApprove
              ? "OmaPilot auto-approves each exact, inspectable device request."
              : "Device changes stay behind an exact, inspectable approval."
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          Toggle {
            Layout.fillWidth: true
            label: "Dangerous auto-approve"
            description: "Approve each exact device action automatically instead of prompting."
            checked: root.dangerousAutoApprove
            enabled: root.backend && !root.backend.busy
            foreground: root.foreground
            accent: checked ? Color.urgent : root.accent
            fontFamily: root.fontFamily
            Accessible.name: label
            onClicked: root.dangerousAutoApproveRequested(!root.dangerousAutoApprove)
          }

          Text {
            Layout.fillWidth: true
            visible: root.dangerousAutoApprove
            text: "Approval prompts are skipped. Commands may read, change, or delete device data and use the network."
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          PanelSeparator {
            Layout.fillWidth: true
            Layout.topMargin: Style.spacing.md
            foreground: root.foreground
          }

          Text {
            Layout.fillWidth: true
            text: "Browser context"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            Layout.fillWidth: true
            text: "Select semantic page elements and choose Element, Text, or Screenshot before sharing context. OmaPilot handles setup from here—no terminal command is required."
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.md

            Rectangle {
              Layout.preferredWidth: Style.space(8)
              Layout.preferredHeight: Style.space(8)
              radius: width / 2
              color: root.browserCompanionConnected ? root.accent
                : (root.browserCompanion.phase === "failed" ? Color.urgent : Color.muted)
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0

              Text {
                Layout.fillWidth: true
                text: root.browserCompanion.phase === "installing" ? "Enabling browser context…"
                  : (root.browserCompanion.phase === "removing" ? "Removing browser context…"
                  : (root.browserCompanionConnected ? "Browser companion connected"
                    : (root.browserCompanion.relayInstalled === true
                      ? "Relay installed · browser restart required"
                      : "Browser companion is off")))
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                wrapMode: Text.Wrap
              }

              Text {
                Layout.fillWidth: true
                text: root.browserCompanionConnected
                  ? "Use the OmaPilot extension icon once per site to grant page access."
                  : (root.browserCompanion.relayInstalled === true
                    ? "Restart Chromium, then pin the OmaPilot extension and enable the current site."
                    : "Choose Enable browser context to install the relay and bundled extension automatically, then restart your browser.")
                color: Qt.darker(root.foreground, 1.45)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
              }
            }
          }

          Text {
            Layout.fillWidth: true
            visible: root.browserCompanion.phase === "failed"
            text: root.browserCompanion.message || "Browser companion setup failed."
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.md

            Button {
              Layout.fillWidth: true
              visible: !root.browserCompanionConnected
              iconText: "󰖟"
              text: root.browserCompanion.relayInstalled === true ? "Repair browser setup" : "Enable browser context"
              tooltipText: "Register the native relay and enable the bundled browser extension"
              foreground: root.foreground
              background: root.background
              accent: root.accent
              active: true
              bordered: true
              focusable: true
              enabled: root.backend && !root.browserCompanionBusy
                && root.browserCompanion.setupAvailable === true
              Accessible.name: tooltipText
              onClicked: {
                root.browserSetupExpanded = true
                root.browserCompanionInstallRequested()
              }
            }

            Button {
              iconText: "󰑓"
              text: "Refresh"
              tooltipText: "Refresh browser companion status"
              foreground: root.foreground
              background: root.background
              bordered: true
              focusable: true
              enabled: root.backend && !root.browserCompanionBusy
              Accessible.name: tooltipText
              onClicked: root.browserCompanionRefreshRequested()
            }
          }

          Button {
            Layout.fillWidth: true
            visible: root.browserCompanion.relayInstalled === true
            text: root.browserSetupExpanded ? "Hide setup details" : (root.browserCompanionConnected ? "Browser setup details" : "Finish browser setup")
            tooltipText: "Open browser extension settings and show the bundled extension folders"
            foreground: root.foreground
            background: root.background
            bordered: true
            focusable: true
            enabled: !root.browserCompanionBusy
            Accessible.name: tooltipText
            onClicked: root.browserSetupExpanded = !root.browserSetupExpanded
          }

          ColumnLayout {
            Layout.fillWidth: true
            visible: root.browserSetupExpanded && root.browserCompanion.relayInstalled === true
            spacing: Style.spacing.lg

            Text {
              Layout.fillWidth: true
              text: "Chromium-family browsers"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Text {
              Layout.fillWidth: true
              text: "Restart the browser first. If the extension is not loaded, open Extensions, enable Developer mode, choose Load unpacked, and select the bundled Chromium folder."
              color: Qt.darker(root.foreground, 1.45)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.md

              Button {
                Layout.fillWidth: true
                text: "Open Chromium extensions"
                foreground: root.foreground
                background: root.background
                bordered: true
                focusable: true
                Accessible.name: text
                onClicked: root.browserCompanionOpenSettingsRequested("chromium")
              }

              Button {
                text: "Copy folder"
                foreground: root.foreground
                background: root.background
                bordered: true
                focusable: true
                enabled: root.browserCompanion.chromiumExtensionPath !== ""
                Accessible.name: "Copy Chromium extension folder path"
                onClicked: root.browserCompanionCopyPathRequested("chromium")
              }
            }

            Text {
              Layout.fillWidth: true
              text: "Firefox and Zen"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Text {
              Layout.fillWidth: true
              text: "Open This Firefox, choose Load Temporary Add-on, then select manifest.json from the bundled Firefox folder. Repeat after each browser restart until a signed store build is available."
              color: Qt.darker(root.foreground, 1.45)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.md

              Button {
                Layout.fillWidth: true
                text: "Open Firefox debugging"
                foreground: root.foreground
                background: root.background
                bordered: true
                focusable: true
                Accessible.name: text
                onClicked: root.browserCompanionOpenSettingsRequested("firefox")
              }

              Button {
                text: "Copy folder"
                foreground: root.foreground
                background: root.background
                bordered: true
                focusable: true
                enabled: root.browserCompanion.firefoxExtensionPath !== ""
                Accessible.name: "Copy Firefox extension folder path"
                onClicked: root.browserCompanionCopyPathRequested("firefox")
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            visible: root.browserCompanion.relayInstalled === true || root.browserRemoveConfirmation
            spacing: Style.spacing.md

            Button {
              Layout.fillWidth: true
              iconText: "󰆴"
              text: root.browserRemoveConfirmation ? "Confirm removal" : "Remove browser context"
              tooltipText: root.browserRemoveConfirmation
                ? "Confirm removal of the native relay, browser registrations, and extension flags"
                : "Remove the native relay, browser registrations, and extension flags"
              foreground: root.foreground
              background: root.background
              accent: Color.urgent
              active: root.browserRemoveConfirmation
              bordered: true
              focusable: true
              enabled: root.backend && !root.browserCompanionBusy
                && root.browserCompanion.setupAvailable === true
              Accessible.name: tooltipText
              onClicked: {
                if (!root.browserRemoveConfirmation) {
                  root.browserRemoveConfirmation = true
                  return
                }
                root.browserRemoveConfirmation = false
                root.browserCompanionUninstallRequested()
              }
            }

            Button {
              visible: root.browserRemoveConfirmation
              text: "Cancel"
              tooltipText: "Keep browser context enabled"
              foreground: root.foreground
              background: root.background
              bordered: true
              focusable: true
              enabled: !root.browserCompanionBusy
              Accessible.name: tooltipText
              onClicked: root.browserRemoveConfirmation = false
            }
          }

          Text {
            Layout.fillWidth: true
            visible: !root.browserCompanionConnected && root.browserCompanion.relayInstalled !== true
            text: "OmaPilot registers the native-messaging host and adds its bundled extension to detected Omarchy Chromium-family browsers for you. Firefox and Zen still require browser confirmation to load the temporary Firefox build."
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          PanelSeparator {
            Layout.fillWidth: true
            Layout.topMargin: Style.spacing.md
            foreground: root.foreground
          }

          Text {
            Layout.fillWidth: true
            text: "Harness"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Dropdown {
            id: providerPicker
            Layout.fillWidth: true
            showLabel: false
            options: root.modeProviders
            value: root.backend ? root.backend.provider : ""
            enabled: root.backend && !root.backend.busy
            foreground: root.foreground
            background: root.background
            Accessible.name: "Agent harness"
            onChanged: function(value) { root.providerChanged(value) }
          }

          Text {
            Layout.fillWidth: true
            text: "Model"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Dropdown {
            id: modelPicker
            Layout.fillWidth: true
            showLabel: false
            options: root.backend && root.backend.modelOptions.length > 0
              ? root.backend.modelOptions
              : [{ value: "", label: "Harness default" }]
            value: root.backend ? root.backend.model : ""
            enabled: root.backend && !root.backend.busy
            foreground: root.foreground
            background: root.background
            Accessible.name: "AI model"
            onChanged: function(value) {
              root.backend.model = value
              root.modelChanged(root.backend.provider, value)
            }
          }

          Text {
            Layout.fillWidth: true
            visible: root.backend
            text: !root.backend ? "" : Protocol.providerPolicyDescription(root.backend.provider, root.backend.providerPolicy)
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          Text {
            Layout.fillWidth: true
            visible: root.backend && root.backend.modelOptions.length === 0
            text: "Using the harness default. This harness did not expose a model catalog."
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          PanelSeparator {
            Layout.fillWidth: true
            Layout.topMargin: Style.spacing.md
            foreground: root.foreground
          }

          Text {
            Layout.fillWidth: true
            text: "Quick actions"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            Layout.fillWidth: true
            text: "Add, edit, remove, or reorder the prompts shown on an empty conversation."
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          QuickActionEditor {
            Layout.fillWidth: true
            actions: root.quickActions
            foreground: root.foreground
            background: root.background
            accent: root.accent
            fontFamily: root.fontFamily
            onActionsEdited: function(actions) { root.quickActionsEdited(actions) }
          }

          PanelSeparator {
            Layout.fillWidth: true
            Layout.topMargin: Style.spacing.md
            foreground: root.foreground
          }

          Text {
            Layout.fillWidth: true
            text: "Conversation"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Button {
            Layout.fillWidth: true
            iconText: "󰋚"
            text: "Recent chats"
            tooltipText: "Browse up to 30 completed answers"
            foreground: root.foreground
            background: root.background
            bordered: true
            focusable: true
            Accessible.name: tooltipText
            onClicked: root.recentChatsRequested()
          }
        }
      }
    }
  }
}
