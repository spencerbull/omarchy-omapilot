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
  property bool desktopContextEnabled: true
  property string webHandoffProvider: "duckduckgo"
  property var quickActions: []
  property string selectedTab: "agent"
  property bool motionEnabled: true
  property color foreground: OmaPilotPalette.popups.text
  property color background: OmaPilotPalette.popups.background
  property color accent: OmaPilotPalette.accent
  property string fontFamily: Style.font.family
  readonly property var modeProviders: Protocol.harnessOptions()
  readonly property var browserCompanion: backend && backend.browserCompanionStatus
    ? backend.browserCompanionStatus : ({
      phase: "ready", relayInstalled: false, setupAvailable: false,
      chromiumConnected: false, firefoxConnected: false,
      chromiumExtensionPath: "", firefoxExtensionPath: "", message: ""
    })
  readonly property var voxtypeOsd: backend && backend.voxtypeOsd
    ? backend.voxtypeOsd : ({ available: false, enabled: true, message: "" })
  readonly property var voiceStatus: backend && backend.voiceStatus
    ? backend.voiceStatus : Protocol.emptyVoiceStatus()
  property bool voiceEnabled: false
  property string voiceVisualizer: "segments"
  property string thinkingVisualizer: "bumper"
  property string ttsProvider: "elevenlabs"
  property string ttsModel: ""
  property string ttsVoice: ""
  property string ttsDraftKey: ""
  property bool ttsKeyBusy: false
  property string ttsFormError: ""
  property string ttsFormNotice: ""
  readonly property var ttsCatalog: Protocol.ttsProviderStatus(voiceStatus, ttsProvider)
  readonly property bool ttsCloud: ttsProvider === "elevenlabs" || ttsProvider === "openai"
  readonly property bool dictationReady: voiceStatus.dictation && voiceStatus.dictation.available === true
  readonly property bool ttsReady: ttsCatalog && ttsCatalog.available === true
  // Guarded like browserCompanion: the offscreen contract harness injects a stub
  // backend with neither property.
  readonly property var savedServers: backend && backend.customProviders
    ? backend.customProviders : []
  readonly property var capabilities: backend && backend.capabilities
    ? backend.capabilities : []
  readonly property string capabilityError: backend && backend.capabilityError
    ? String(backend.capabilityError) : ""
  property string filesRootDraft: ""
  readonly property string brokerServerError: backend && backend.customProviderError
    ? String(backend.customProviderError) : ""
  readonly property bool browserCompanionConnected: backend ? backend.browserCompanionConnected === true : false
  readonly property bool browserCompanionBusy: backend ? backend.browserCompanionBusy === true : false
  readonly property bool hotkeyBusy: backend ? backend.hotkeyBusy === true : false
  readonly property string hotkeyMessage: backend ? String(backend.hotkeyMessage || "") : ""
  property bool browserRemoveConfirmation: false
  property bool browserSetupExpanded: false
  // Add-an-endpoint form state. Nothing here is persisted until the broker
  // validates it, so these are plain drafts.
  property bool serverFormExpanded: false
  property string serverDraftId: ""
  property string serverDraftName: ""
  property string serverDraftUrl: ""
  property string serverDraftKey: ""
  property var serverTestModels: []
  property string serverTestUrl: ""
  property var serverOriginalModels: []
  property string serverOriginalUrl: ""
  property bool serverTestPending: false
  // Non-empty while editing an existing server; its id is then fixed, because
  // changing the id would create a second entry rather than rename this one.
  property string serverEditingId: ""
  // Chat Completions is the broadest interoperable default for local OpenAI-
  // compatible servers, especially for multi-step tool conversations.
  property bool serverDraftResponses: false
  property string serverRemoveConfirmId: ""
  // Why a save was refused, and confirmation that one landed. A disabled button
  // with no explanation is indistinguishable from a broken one.
  property string serverFormError: ""
  property string serverFormNotice: ""
  property bool serverSavePending: false
  property string serverPendingId: ""
  property string serverPendingName: ""
  // True only while no provider has been authenticated at all.
  readonly property bool authenticationRequired: !root.backend
    || (root.backend.state === "unavailable" && root.backend.providers.length === 0)
  property string selectedAuthMethod: ""
  property string authPromptSelection: ""
  readonly property bool popupOpen: providerPicker.popupOpen || modelPicker.popupOpen
    || authMethodPicker.popupOpen || authPromptPicker.popupOpen
    || webHandoffProviderPicker.popupOpen || ttsProviderPicker.popupOpen
    || ttsModelPicker.popupOpen || ttsVoicePicker.popupOpen
    || voiceVisualizerPicker.popupOpen || thinkingVisualizerPicker.popupOpen
  readonly property bool modalInteractionActive: popupOpen
    || browserCompanionBusy
    || (selectedTab === "desktop" && browserRemoveConfirmation)
    || (selectedTab === "actions" && quickActionEditor.interactionActive)
    || (selectedTab === "servers" && serverRemoveConfirmId !== "")
  implicitHeight: Style.space(560)
  readonly property color mutedForeground: OmaPilotPalette.darkForeground
  Accessible.name: "OmaPilot settings"

  signal dangerousAutoApproveRequested(bool enabled)
  signal desktopContextRequested(bool enabled)
  signal webHandoffProviderRequested(string provider)
  signal capabilityEnabledRequested(string capabilityId, bool enabled)
  signal capabilityFilesRootRequested(string path)
  signal capabilitiesRefreshRequested()
  signal providerChanged(string provider)
  signal modelChanged(string provider, string model)
  signal quickActionsEdited(var actions)
  signal browserCompanionInstallRequested()
  signal browserCompanionUninstallRequested()
  signal browserCompanionRefreshRequested()
  signal browserCompanionOpenSettingsRequested(string family)
  signal browserCompanionCopyPathRequested(string family)
  signal hotkeyInstallRequested()
  signal hotkeyRemoveRequested()
  signal customProviderAddRequested(string id, string name, string baseUrl, string api, var models, string apiKey)
  signal customProviderTestRequested(string baseUrl, string apiKey)
  signal customProviderRemoveRequested(string id)
  signal voxtypeOsdRequested(bool enabled)
  signal voiceEnabledRequested(bool enabled)
  signal voiceVisualizerRequested(string visualizer)
  signal thinkingVisualizerRequested(string visualizer)
  signal ttsProviderRequested(string provider)
  signal ttsModelRequested(string model)
  signal ttsVoiceRequested(string voice)
  signal ttsKeySetRequested(string provider, string apiKey)
  signal ttsKeyClearRequested(string provider)
  signal ttsKeyTestRequested(string provider, string apiKey)
  signal dismissed()

  function resetServerForm() {
    serverFormError = ""
    serverFormExpanded = false
    serverEditingId = ""
    serverDraftId = ""
    serverDraftName = ""
    serverDraftUrl = ""
    serverDraftKey = ""
    serverTestModels = []
    serverTestUrl = ""
    serverOriginalModels = []
    serverOriginalUrl = ""
    serverTestPending = false
    serverDraftResponses = false
    serverRemoveConfirmId = ""
    serverSavePending = false
    serverPendingId = ""
    serverPendingName = ""
  }

  function invalidateServerTest() {
    serverTestModels = []
    serverTestUrl = ""
    serverTestPending = false
  }

  function refreshServerTestValidity() {
    if (serverEditingId !== "" && serverDraftKey.trim() === ""
        && serverDraftUrl.trim() === serverOriginalUrl
        && serverOriginalModels.length > 0) {
      serverTestModels = serverOriginalModels
      serverTestUrl = serverOriginalUrl
      serverTestPending = false
      return
    }
    invalidateServerTest()
  }

  function selectTab(id) {
    var next = Presentation.normalizedSettingsTab(id)
    if (next === selectedTab) return
    closePopups(false)
    // Confirmations and the add-action editor are tab-local. Leaving them
    // armed keeps modalInteractionActive true while their controls are gone,
    // which swallows Ctrl+H and panel navigation.
    if (next !== "servers") serverRemoveConfirmId = ""
    if (next !== "desktop") browserRemoveConfirmation = false
    if (next !== "actions" && quickActionEditor.adding) quickActionEditor.cancelAdding()
    selectedTab = next
    if (next === "skills") filesRootDraft = Protocol.capabilityFilesRoot(capabilities)
  }

  Connections {
    target: root.backend

    function onCapabilitiesChanged() {
      if (!filesRootField.activeFocus)
        root.filesRootDraft = Protocol.capabilityFilesRoot(root.capabilities)
    }

    function onCustomProviderSavedChanged() {
      var saved = root.backend ? root.backend.customProviderSaved : null
      if (!root.serverSavePending || !saved
          || String(saved.id || "") !== root.serverPendingId) return
      var savedName = root.serverPendingName
      root.resetServerForm()
      root.serverFormNotice = "Saved " + savedName + "."
    }

    function onCustomProviderErrorChanged() {
      if (!root.serverSavePending || root.brokerServerError === "") return
      root.serverSavePending = false
      root.serverFormError = root.brokerServerError
    }

    function onCustomProviderTestChanged() {
      var result = root.backend ? root.backend.customProviderTest : null
      if (!root.serverTestPending || !result) return
      root.serverTestPending = false
      root.serverDraftUrl = String(result.baseUrl || root.serverDraftUrl)
      root.serverTestUrl = root.serverDraftUrl
      root.serverTestModels = Array.isArray(result.models) ? result.models : []
      root.serverFormError = ""
    }

    function onCustomProviderTestErrorChanged() {
      var message = root.backend ? String(root.backend.customProviderTestError || "") : ""
      if (!root.serverTestPending || message === "") return
      root.serverTestPending = false
      root.serverFormError = message
    }

    function onVoiceStatusChanged() {
      if (root.ttsKeyBusy) {
        root.ttsKeyBusy = false
        root.ttsFormError = ""
        root.ttsDraftKey = ""
        root.ttsFormNotice = root.ttsCloud
          ? (root.ttsCatalog.available ? "API key saved." : String(root.ttsCatalog.message || "The API key was saved."))
          : ""
      }
      root.syncTtsSelection()
    }

    function onTtsTestChanged() {
      if (!root.ttsKeyBusy || !root.backend || !root.backend.ttsTest) return
      root.ttsKeyBusy = false
      root.ttsFormError = ""
      root.ttsFormNotice = "The API key works. Save it to use this provider."
    }

    function onTtsTestErrorChanged() {
      var message = root.backend ? String(root.backend.ttsTestError || "") : ""
      if (!root.ttsKeyBusy || message === "") return
      root.ttsKeyBusy = false
      root.ttsFormError = message
    }
  }

  function syncTtsSelection() {
    var catalog = Protocol.ttsProviderStatus(root.voiceStatus, root.ttsProvider)
    var model = root.ttsModel
    if (!Protocol.ttsModelAvailable(catalog, model)) {
      model = Protocol.ttsDefaultModel(catalog)
      if (model !== root.ttsModel) root.ttsModelRequested(model)
    }
    if (!Protocol.ttsVoiceAvailable(catalog, model, root.ttsVoice)) {
      var voice = Protocol.ttsDefaultVoice(catalog, model)
      if (voice !== root.ttsVoice) root.ttsVoiceRequested(voice)
    }
  }

  function editServer(server) {
    serverFormError = ""
    serverFormNotice = ""
    serverEditingId = String(server.id || "")
    serverDraftId = serverEditingId
    serverDraftName = String(server.name || "")
    serverDraftUrl = String(server.baseUrl || "")
    // Left blank on purpose: the stored credential is not readable here. Saving
    // without a replacement key preserves it only while the endpoint stays the
    // same; moving to another endpoint clears it so secrets never cross hosts.
    serverDraftKey = ""
    // The saved model set already came from a successful /models probe. Keep it
    // valid while the endpoint is unchanged so a keyed server can be renamed or
    // have its API mode updated without re-entering a write-only credential.
    // Editing either the URL or key still calls invalidateServerTest().
    var savedModels = Array.isArray(server.models) ? server.models : []
    serverOriginalModels = savedModels.map(function(model) {
      var id = String(model && typeof model === "object" ? model.id : model || "").trim()
      var name = String(model && typeof model === "object" ? model.name || id : id).trim()
      var contextWindow = Number(model && typeof model === "object" ? model.contextWindow : 0)
      return {
        id: id,
        name: name || id,
        contextWindow: isFinite(contextWindow) && contextWindow > 0 ? Math.floor(contextWindow) : 128000
      }
    }).filter(function(model) { return model.id !== "" })
    serverOriginalUrl = serverDraftUrl.trim()
    serverTestModels = serverOriginalModels
    serverTestUrl = serverTestModels.length > 0 ? serverOriginalUrl : ""
    serverDraftResponses = String(server.api || "") !== "openai-completions"
    serverRemoveConfirmId = ""
    serverFormExpanded = true
    selectTab("servers")
  }

  function closePopups(restoreFocus) {
    providerPicker.close()
    modelPicker.close()
    authMethodPicker.close()
    authPromptPicker.close()
    webHandoffProviderPicker.close()
    ttsProviderPicker.close()
    ttsModelPicker.close()
    ttsVoicePicker.close()
    voiceVisualizerPicker.close()
    thinkingVisualizerPicker.close()
    if (restoreFocus !== false)
      Qt.callLater(function() { tabBar.forceActiveFocus() })
  }

  function forceInitialFocus() {
    if (root.authenticationRequired) selectTab("agent")
    tabBar.forceActiveFocus()
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
        Layout.alignment: Qt.AlignVCenter
        iconText: "󰁍"
        tooltipText: "Back to conversation"
        foreground: root.foreground
        focusable: true
        Accessible.name: tooltipText
        onClicked: root.dismissed()
      }

      Text {
        text: "Settings"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        Accessible.role: Accessible.Heading
        Accessible.name: text
      }

      SettingsTabs {
        id: tabBar
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        current: root.selectedTab
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        motionEnabled: root.motionEnabled
        onSelected: function(id) { root.selectTab(id) }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.spacing.hairline
      color: OmaPilotPalette.normalBorder(root.foreground)
      Accessible.ignored: true
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.leftMargin: Style.spacing.panelPadding
      Layout.rightMargin: Style.spacing.panelPadding
      Layout.topMargin: Style.spacing.xxxl
      Layout.bottomMargin: Style.space(15)

      Flickable {
        id: agentScroll
        anchors.fill: parent
        visible: root.selectedTab === "agent"
        contentWidth: width
        contentHeight: agentContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ColumnLayout {
          id: agentContent
          width: agentScroll.width
          spacing: Style.spacing.xxl

          Text {
            Layout.fillWidth: true
            text: "Harness"
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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
            color: root.mutedForeground
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
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          ColumnLayout {
            Layout.fillWidth: true
            visible: root.backend && root.backend.provider === "builtin"
            spacing: Style.spacing.md

            Text {
              Layout.fillWidth: true
              text: root.authenticationRequired ? "Authentication required" : "Accounts"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: root.authenticationRequired ? Style.font.body : Style.font.caption
              font.bold: true
            }

            Text {
              Layout.fillWidth: true
              text: root.authenticationRequired
                ? "Sign in with a subscription or API key. Credentials stay in OmaPilot's private configuration."
                : "Add Codex, OpenAI, Grok, or a server from the Servers tab."
              color: root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
              Accessible.role: Accessible.StaticText
              Accessible.name: text
            }

            Dropdown {
              id: authMethodPicker
              Layout.fillWidth: true
              visible: root.backend && !root.backend.builtinAuthBusy
              showLabel: false
              options: root.backend ? root.backend.builtinAuthMethods : []
              value: root.selectedAuthMethod || (options.length > 0 ? String(options[0].value || "") : "")
              enabled: options.length > 0
              foreground: root.foreground
              background: root.background
              Accessible.name: "Built-in authentication method"
              onChanged: function(value) { root.selectedAuthMethod = value }
            }

            Text {
              Layout.fillWidth: true
              visible: root.backend && String(root.backend.builtinAuth.message || "") !== ""
              text: root.backend ? String(root.backend.builtinAuth.message || "") : ""
              color: root.backend && String(root.backend.builtinAuth.phase || "") === "error"
                ? OmaPilotPalette.urgent : root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            RowLayout {
              Layout.fillWidth: true
              visible: root.backend && (String(root.backend.builtinAuth.url || "") !== ""
                || String(root.backend.builtinAuth.verificationUri || "") !== "")
              spacing: Style.spacing.md

              CompactSettingsButton {
                text: "Open sign-in page"
                iconText: "󰖟"
                foreground: root.foreground
                background: root.background
                accent: root.accent
                active: true
                bordered: true
                focusable: true
                onClicked: root.backend.activateLink(String(root.backend.builtinAuth.url
                  || root.backend.builtinAuth.verificationUri || ""))
              }

              CompactSettingsButton {
                visible: root.backend && String(root.backend.builtinAuth.userCode || "") !== ""
                text: "Copy " + (root.backend ? String(root.backend.builtinAuth.userCode || "") : "")
                foreground: root.foreground
                background: root.background
                bordered: true
                focusable: true
                onClicked: root.backend.copyText(String(root.backend.builtinAuth.userCode || ""))
              }

              Item { Layout.fillWidth: true }
            }

            Text {
              Layout.fillWidth: true
              visible: root.backend && root.backend.builtinAuth.prompt
              text: visible ? String(root.backend.builtinAuth.prompt.message || "") : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            Dropdown {
              id: authPromptPicker
              Layout.fillWidth: true
              visible: root.backend && root.backend.builtinAuth.prompt
                && root.backend.builtinAuth.prompt.kind === "select"
              showLabel: false
              options: visible ? root.backend.builtinAuth.prompt.options : []
              value: root.authPromptSelection || (options.length > 0 ? String(options[0].value || "") : "")
              foreground: root.foreground
              background: root.background
              Accessible.name: visible ? String(root.backend.builtinAuth.prompt.message || "Authentication choice") : "Authentication choice"
              onChanged: function(value) { root.authPromptSelection = value }
            }

            TextField {
              id: authPromptInput
              Layout.fillWidth: true
              verticalPadding: Style.spacing.controlPaddingY
              visible: root.backend && root.backend.builtinAuth.prompt
                && root.backend.builtinAuth.prompt.kind !== "select"
              password: visible && root.backend.builtinAuth.prompt.kind === "secret"
              placeholderText: visible ? String(root.backend.builtinAuth.prompt.placeholder
                || root.backend.builtinAuth.prompt.message || "") : ""
              maximumLength: 32768
              foreground: root.foreground
              accent: root.accent
              Accessible.name: visible ? String(root.backend.builtinAuth.prompt.message || "Authentication value") : "Authentication value"
              onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
              onAccepted: if (visible) root.backend.respondBuiltInAuth(text)
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.md

              CompactSettingsButton {
                visible: root.backend && !root.backend.builtinAuthBusy
                text: String(root.backend && root.backend.builtinAuth.phase || "") === "error" ? "Try again"
                  : (root.authenticationRequired ? "Continue" : "Sign in")
                iconText: "󰌾"
                foreground: root.foreground
                background: root.background
                accent: root.accent
                active: true
                bordered: true
                focusable: true
                enabled: authMethodPicker.options.length > 0
                onClicked: root.backend.authenticateBuiltIn(authMethodPicker.value)
              }

              CompactSettingsButton {
                visible: root.backend && root.backend.builtinAuth.prompt
                text: "Continue"
                foreground: root.foreground
                background: root.background
                accent: root.accent
                active: true
                bordered: true
                focusable: true
                enabled: root.backend && root.backend.builtinAuth.prompt
                  ? (root.backend.builtinAuth.prompt.kind === "select"
                    ? authPromptPicker.value !== "" : authPromptInput.text !== "") : false
                onClicked: root.backend.respondBuiltInAuth(root.backend.builtinAuth.prompt.kind === "select"
                  ? authPromptPicker.value : authPromptInput.text)
              }

              CompactSettingsButton {
                visible: root.backend && root.backend.builtinAuthBusy
                text: "Cancel"
                foreground: root.foreground
                background: root.background
                bordered: true
                focusable: true
                onClicked: root.backend.cancelBuiltInAuth()
              }

              Item { Layout.fillWidth: true }
            }
          }
        }
      }

      Flickable {
        id: skillsScroll
        anchors.fill: parent
        visible: root.selectedTab === "skills"
        contentWidth: width
        contentHeight: skillsContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ColumnLayout {
          id: skillsContent
          width: skillsScroll.width
          spacing: Style.spacing.xxl

          Text {
            Layout.fillWidth: true
            text: "Personal capability packs give the agent typed, bounded ways to work with your apps. Reading is automatic; sends and device actions still require review."
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }

          Text {
            Layout.fillWidth: true
            visible: !root.backend || root.backend.brokerCapabilityPacksSupported !== true
            text: "Capability packs require an updated OmaPilot runtime."
            color: OmaPilotPalette.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }

          Repeater {
            model: root.capabilities

            ColumnLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: Style.spacing.sm

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.md

                Rectangle {
                  Layout.preferredWidth: Style.spacing.xxs
                  Layout.preferredHeight: Style.space(36)
                  radius: Style.space(1)
                  color: modelData.state === "ready" ? root.accent
                    : (modelData.state === "degraded" ? OmaPilotPalette.urgent : OmaPilotPalette.muted)
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0

                  Text {
                    Layout.fillWidth: true
                    text: modelData.label + "  ·  " + modelData.connector
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    Layout.fillWidth: true
                    text: modelData.status
                    color: modelData.state === "ready" ? OmaPilotPalette.darkForeground
                      : (modelData.state === "degraded" ? OmaPilotPalette.urgent : root.accent)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.Wrap
                  }
                }

                CompactSettingsToggle {
                  Layout.alignment: Qt.AlignVCenter
                  checked: modelData.enabled
                  enabled: root.backend && root.backend.brokerCapabilityPacksSupported === true
                  foreground: root.foreground
                  accent: root.accent
                  accessibleName: modelData.label + " capability"
                  onClicked: root.capabilityEnabledRequested(modelData.id, !modelData.enabled)
                }
              }

              Text {
                Layout.fillWidth: true
                text: modelData.description
                color: root.mutedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
              }

              Text {
                Layout.fillWidth: true
                text: Protocol.capabilityOperationsLabel(modelData)
                color: OmaPilotPalette.darkForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
              }

              Text {
                Layout.fillWidth: true
                visible: modelData.setupHint !== "" && modelData.state !== "disabled"
                text: modelData.setupHint
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: "Files root"
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            Layout.fillWidth: true
            text: "Choose one specific local or synced folder. OmaPilot will not follow links outside it. Leave blank to disconnect Files."
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.md

            TextField {
              id: filesRootField
              Layout.fillWidth: true
              verticalPadding: Style.spacing.controlPaddingY
              placeholderText: "/home/you/Dropbox"
              maximumLength: 4096
              text: root.filesRootDraft
              enabled: root.backend && root.backend.brokerCapabilityPacksSupported === true
              foreground: root.foreground
              accent: root.accent
              Accessible.name: "Files capability root"
              onTextEdited: root.filesRootDraft = text
              onAccepted: root.capabilityFilesRootRequested(root.filesRootDraft)
            }

            CompactSettingsButton {
              text: "Save"
              foreground: root.foreground
              background: root.background
              accent: root.accent
              active: true
              bordered: true
              focusable: true
              enabled: root.backend && root.backend.brokerCapabilityPacksSupported === true
              onClicked: root.capabilityFilesRootRequested(root.filesRootDraft)
            }
          }

          Text {
            Layout.fillWidth: true
            visible: root.capabilityError !== ""
            text: root.capabilityError
            color: OmaPilotPalette.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }

          CompactSettingsButton {
            text: "Refresh connector status"
            foreground: root.foreground
            background: root.background
            bordered: true
            focusable: true
            enabled: root.backend && root.backend.brokerCapabilityPacksSupported === true
            onClicked: root.capabilitiesRefreshRequested()
          }
        }
      }

      Flickable {
        id: voiceScroll
        anchors.fill: parent
        visible: root.selectedTab === "voice"
        contentWidth: width
        contentHeight: voiceContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ColumnLayout {
          id: voiceContent
          width: voiceScroll.width
          spacing: Style.spacing.xxl

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "Voice stays off after install until you enable it here. Listening uses Voxtype; spoken answers use the TTS provider you choose."
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          CompactSettingsToggle {
            Layout.fillWidth: true
            label: "Enable voice"
            description: root.voiceEnabled
              ? (root.dictationReady
                ? (root.ttsReady
                  ? "Listening and speaking are ready."
                  : "Listening is ready. Finish TTS setup below to hear answers.")
                : "Voice is on, but dictation still needs Voxtype.")
              : "Turn this on to talk to OmaPilot and, once a TTS provider is ready, hear answers."
            checked: root.voiceEnabled
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: root.voiceEnabledRequested(!root.voiceEnabled)
          }

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            visible: root.voiceEnabled && (!root.dictationReady || !root.ttsReady)
            text: !root.dictationReady && !root.ttsReady
              ? "Set up listening and speaking below. The talk gesture stays quiet until Voxtype is ready."
              : (!root.dictationReady
                ? "Install Voxtype to listen. The talk gesture cannot start until dictation is ready."
                : "Choose a TTS provider and finish setup to hear answers. Listening already works.")
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            Layout.fillWidth: true
            text: "Listening"
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.dictationReady
              ? "Voxtype is ready. It is the speech-to-text provider for OmaPilot."
              : String(root.voiceStatus.dictation.message || "Voxtype is not installed. Install it, then reopen settings.")
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            Layout.fillWidth: true
            text: "Listening visualizer"
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Dropdown {
            id: voiceVisualizerPicker
            Layout.fillWidth: true
            showLabel: false
            options: Protocol.voiceVisualizerOptions()
            value: Protocol.normalizedVoiceVisualizer(root.voiceVisualizer) || "segments"
            foreground: root.foreground
            background: root.background
            Accessible.name: "Listening visualizer"
            onChanged: function(value) { root.voiceVisualizerRequested(value) }
          }

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "This changes the live microphone display. AI speech keeps the animated line."
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            Layout.fillWidth: true
            text: "Thinking visualizer"
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Dropdown {
            id: thinkingVisualizerPicker
            Layout.fillWidth: true
            showLabel: false
            options: Protocol.thinkingVisualizerOptions()
            value: Protocol.normalizedThinkingVisualizer(root.thinkingVisualizer) || "bumper"
            foreground: root.foreground
            background: root.background
            Accessible.name: "Thinking visualizer"
            onChanged: function(value) { root.thinkingVisualizerRequested(value) }
          }

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "Shown after dictation while OmaPilot prepares the answer."
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          CompactSettingsToggle {
            Layout.fillWidth: true
            visible: root.voxtypeOsd.available
            label: "Voxtype on-screen display"
            description: "Off leaves OmaPilot's glow as the only recording indicator. Restarts the Voxtype daemon."
            checked: root.voxtypeOsd.enabled
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: root.voxtypeOsdRequested(!root.voxtypeOsd.enabled)
          }

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            visible: !root.voxtypeOsd.available
            text: "Voxtype's configuration was not found, so its on-screen display cannot be switched from here."
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            visible: String(root.voxtypeOsd.message || "") !== ""
            text: String(root.voxtypeOsd.message || "")
            color: OmaPilotPalette.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            Layout.fillWidth: true
            text: "Speaking"
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "ElevenLabs is the guided default. Add its API key here for spoken replies. Kokoro runs locally; cloud keys stay in voice-auth.json — never in widget settings."
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Dropdown {
            id: ttsProviderPicker
            Layout.fillWidth: true
            showLabel: false
            options: Protocol.ttsProviderOptions()
            value: root.ttsProvider
            foreground: root.foreground
            background: root.background
            Accessible.name: "TTS provider"
            onChanged: function(value) {
              root.ttsDraftKey = ""
              root.ttsFormError = ""
              root.ttsFormNotice = ""
              root.ttsProviderRequested(value)
            }
          }

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            visible: String(root.ttsCatalog.message || "") !== ""
            text: String(root.ttsCatalog.message || "")
            color: root.ttsReady ? root.mutedForeground : OmaPilotPalette.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          TextField {
            id: ttsKeyInput
            Layout.fillWidth: true
            verticalPadding: Style.spacing.controlPaddingY
            visible: root.ttsCloud
            password: true
            placeholderText: root.ttsCatalog.configured
              ? "New API key (leave blank to keep the saved key)"
              : (root.ttsProvider === "elevenlabs" ? "ElevenLabs API key" : "OpenAI API key")
            maximumLength: 512
            text: root.ttsDraftKey
            foreground: root.foreground
            accent: root.accent
            Accessible.name: "TTS API key"
            onTextChanged: {
              root.ttsDraftKey = text
              root.ttsFormNotice = ""
            }
          }

          RowLayout {
            Layout.fillWidth: true
            visible: root.ttsCloud
            spacing: Style.spacing.md

            CompactSettingsButton {
              text: "Test key"
              foreground: root.foreground
              background: root.background
              bordered: true
              focusable: true
              enabled: !root.ttsKeyBusy && root.ttsDraftKey.trim() !== ""
              onClicked: {
                root.ttsFormError = ""
                root.ttsFormNotice = ""
                root.ttsKeyBusy = true
                root.ttsKeyTestRequested(root.ttsProvider, root.ttsDraftKey)
              }
            }

            CompactSettingsButton {
              text: root.ttsCatalog.configured ? "Replace key" : "Save key"
              foreground: root.foreground
              background: root.background
              accent: root.accent
              active: true
              bordered: true
              focusable: true
              enabled: !root.ttsKeyBusy && root.ttsDraftKey.trim() !== ""
              onClicked: {
                root.ttsFormError = ""
                root.ttsFormNotice = ""
                root.ttsKeyBusy = true
                root.ttsKeySetRequested(root.ttsProvider, root.ttsDraftKey)
              }
            }

            CompactSettingsButton {
              visible: root.ttsCatalog.configured
              text: "Remove key"
              foreground: root.foreground
              background: root.background
              bordered: true
              focusable: true
              enabled: !root.ttsKeyBusy
              onClicked: {
                root.ttsFormError = ""
                root.ttsFormNotice = ""
                root.ttsDraftKey = ""
                root.ttsKeyClearRequested(root.ttsProvider)
              }
            }

            Item { Layout.fillWidth: true }
          }

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            visible: root.ttsFormError !== ""
            text: root.ttsFormError
            color: OmaPilotPalette.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            visible: root.ttsFormNotice !== ""
            text: root.ttsFormNotice
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            Layout.fillWidth: true
            text: "TTS model"
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Dropdown {
            id: ttsModelPicker
            Layout.fillWidth: true
            showLabel: false
            options: Protocol.ttsModelOptions(root.ttsCatalog)
            value: root.ttsModel
            enabled: Protocol.ttsDefaultModel(root.ttsCatalog) !== ""
            foreground: root.foreground
            background: root.background
            Accessible.name: "TTS model"
            onChanged: function(value) { root.ttsModelRequested(value) }
          }

          Text {
            Layout.fillWidth: true
            text: "TTS voice"
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Dropdown {
            id: ttsVoicePicker
            Layout.fillWidth: true
            showLabel: false
            options: Protocol.ttsVoiceOptions(root.ttsCatalog, root.ttsModel)
            value: root.ttsVoice
            enabled: Protocol.ttsDefaultVoice(root.ttsCatalog, root.ttsModel) !== ""
            foreground: root.foreground
            background: root.background
            Accessible.name: "TTS voice"
            onChanged: function(value) { root.ttsVoiceRequested(value) }
          }
        }
      }

      Flickable {
        id: serversScroll
        anchors.fill: parent
        visible: root.selectedTab === "servers"
        contentWidth: width
        contentHeight: serversContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ColumnLayout {
          id: serversContent
          width: serversScroll.width
          spacing: Style.spacing.xxl

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "Register an OpenAI-compatible /responses or /chat/completions endpoint. Test /models before saving. Keys go to auth.json, never into the definition."
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            Layout.fillWidth: true
            visible: root.savedServers.length === 0 && !root.serverFormExpanded
            text: "No servers added yet."
            color: OmaPilotPalette.darkForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: root.savedServers

            ColumnLayout {
              required property var modelData
              readonly property int liveModels: root.backend && root.backend.modelOptions
                ? Protocol.customProviderModelCount(root.backend.modelOptions, modelData.id) : 0
              Layout.fillWidth: true
              spacing: Style.spacing.sm

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.md

                Rectangle {
                  Layout.preferredWidth: Style.spacing.xxs
                  Layout.preferredHeight: Style.space(28)
                  radius: Style.space(1)
                  color: liveModels > 0 ? root.accent : OmaPilotPalette.muted
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0
                  Text {
                    Layout.fillWidth: true
                    text: modelData.name + "  \u00b7  " + modelData.apiLabel
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                  Text {
                    Layout.fillWidth: true
                    text: modelData.baseUrl + "  \u00b7  " + modelData.models.length
                      + (modelData.models.length === 1 ? " model" : " models")
                    color: OmaPilotPalette.darkForeground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideMiddle
                  }
                  Text {
                    Layout.fillWidth: true
                    text: liveModels > 0
                      ? "Connected \u00b7 " + liveModels + (liveModels === 1 ? " model available" : " models available")
                      : (modelData.requiresAuth
                        ? "Not signed in \u2014 edit this server and enter its API key"
                        : "No API key required \u00b7 refreshing models")
                    color: liveModels > 0 ? OmaPilotPalette.darkForeground : root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                CompactSettingsButton {
                  text: "Edit"
                  foreground: OmaPilotPalette.darkForeground
                  background: root.background
                  bordered: true
                  focusable: true
                  onClicked: root.editServer(modelData)
                }

                CompactSettingsButton {
                  text: root.serverRemoveConfirmId === modelData.id ? "Confirm removal" : "Remove"
                  foreground: root.serverRemoveConfirmId === modelData.id
                    ? OmaPilotPalette.urgent : OmaPilotPalette.darkForeground
                  background: root.background
                  bordered: true
                  focusable: true
                  onClicked: {
                    if (root.serverRemoveConfirmId === modelData.id) {
                      root.customProviderRemoveRequested(modelData.id)
                      root.serverRemoveConfirmId = ""
                    } else root.serverRemoveConfirmId = modelData.id
                  }
                }
              }
            }
          }

          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            visible: root.brokerServerError !== "" && !root.serverFormExpanded
            text: root.brokerServerError
            color: OmaPilotPalette.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            Layout.fillWidth: true
            visible: root.serverFormNotice !== "" && root.brokerServerError === "" && !root.serverFormExpanded
            text: root.serverFormNotice
            color: OmaPilotPalette.darkForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          CompactSettingsButton {
            text: root.serverSavePending ? "Saving…" : (root.serverFormExpanded ? "Cancel" : "Add a server")
            enabled: !root.serverSavePending
            foreground: root.foreground
            background: root.background
            bordered: true
            focusable: true
            onClicked: {
              if (root.serverFormExpanded) root.resetServerForm()
              else { root.serverFormExpanded = true; root.serverRemoveConfirmId = "" }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            visible: root.serverFormExpanded
            spacing: Style.spacing.md

            TextField {
              Layout.fillWidth: true
              verticalPadding: Style.spacing.controlPaddingY
              placeholderText: "Short id, e.g. my-server  (required)"
              maximumLength: 64
              enabled: root.serverEditingId === "" && !root.serverSavePending
              text: root.serverDraftId
              foreground: root.foreground
              accent: root.accent
              onTextEdited: root.serverDraftId = text
            }

            TextField {
              Layout.fillWidth: true
              verticalPadding: Style.spacing.controlPaddingY
              placeholderText: "Display name (optional)"
              maximumLength: 64
              text: root.serverDraftName
              enabled: !root.serverSavePending
              foreground: root.foreground
              accent: root.accent
              onTextEdited: root.serverDraftName = text
            }

            TextField {
              Layout.fillWidth: true
              verticalPadding: Style.spacing.controlPaddingY
              placeholderText: "https://host/v1  (http also supported for localhost or .ts.net)"
              maximumLength: 512
              text: root.serverDraftUrl
              enabled: !root.serverSavePending
              foreground: root.foreground
              accent: root.accent
              onTextEdited: {
                root.serverDraftUrl = text
                root.refreshServerTestValidity()
              }
            }

            TextField {
              Layout.fillWidth: true
              verticalPadding: Style.spacing.controlPaddingY
              placeholderText: root.serverEditingId === ""
                ? "API key (optional; blank means no key is required)"
                : (root.serverDraftUrl.trim() === root.serverOriginalUrl
                  ? "API key (optional; blank keeps the current auth setting)"
                  : "API key (optional; blank clears the old endpoint's key)")
              maximumLength: 512
              password: true
              text: root.serverDraftKey
              enabled: !root.serverSavePending
              foreground: root.foreground
              accent: root.accent
              onTextEdited: {
                root.serverDraftKey = text
                root.refreshServerTestValidity()
              }
            }

            CompactSettingsButton {
              text: root.serverTestPending ? "Testing /models…" : "Test server"
              enabled: !root.serverSavePending && !root.serverTestPending
              foreground: root.foreground
              background: root.background
              accent: root.accent
              active: root.serverTestModels.length > 0
              bordered: true
              focusable: true
              onClicked: {
                if (root.serverDraftUrl.trim() === "") {
                  root.serverFormError = "Add a URL before testing the server."
                  return
                }
                root.serverFormError = ""
                root.serverTestModels = []
                root.serverTestUrl = ""
                root.serverTestPending = true
                root.customProviderTestRequested(root.serverDraftUrl, root.serverDraftKey)
              }
            }

            Text {
              Layout.fillWidth: true
              visible: root.serverTestModels.length > 0
              text: "Found " + root.serverTestModels.length
                + (root.serverTestModels.length === 1 ? " model: " : " models: ")
                + root.serverTestModels.map(function(model) { return String(model.id || "") }).join(", ")
              color: OmaPilotPalette.darkForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            CompactSettingsToggle {
              Layout.fillWidth: true
              enabled: !root.serverSavePending
              checked: root.serverDraftResponses
              label: "Use the /responses API"
              description: "Turn off for servers that only implement /chat/completions."
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.serverDraftResponses = !root.serverDraftResponses
            }

            Text {
              Layout.fillWidth: true
              wrapMode: Text.Wrap
              visible: root.serverFormError !== "" || root.brokerServerError !== ""
              text: root.serverFormError !== "" ? root.serverFormError : root.brokerServerError
              color: OmaPilotPalette.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            CompactSettingsButton {
              text: root.serverSavePending ? "Saving server…"
                : (root.serverEditingId === "" ? "Save server" : "Update server")
              enabled: !root.serverSavePending
              foreground: root.foreground
              background: root.background
              accent: root.accent
              active: true
              bordered: true
              focusable: true
              onClicked: {
                var missing = []
                if (root.serverDraftId.trim() === "") missing.push("an id")
                if (root.serverDraftUrl.trim() === "") missing.push("a URL")
                if (root.serverTestModels.length === 0 || root.serverTestUrl === "") missing.push("a successful server test")
                if (missing.length > 0) {
                  root.serverFormError = "Add " + missing.join(", ") + " before saving."
                  return
                }
                var savedName = root.serverDraftName.trim() !== ""
                  ? root.serverDraftName.trim() : root.serverDraftId.trim()
                root.serverFormError = ""
                root.serverFormNotice = ""
                root.serverSavePending = true
                root.serverPendingId = root.serverDraftId.trim().toLowerCase()
                root.serverPendingName = savedName
                root.customProviderAddRequested(
                  root.serverDraftId, root.serverDraftName, root.serverDraftUrl,
                  root.serverDraftResponses ? "openai-responses" : "openai-completions",
                  root.serverTestModels, root.serverDraftKey)
              }
            }
          }
        }
      }

      Flickable {
        id: desktopScroll
        anchors.fill: parent
        visible: root.selectedTab === "desktop"
        contentWidth: width
        contentHeight: desktopContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ColumnLayout {
          id: desktopContent
          width: desktopScroll.width
          spacing: Style.spacing.xxl

          CompactSettingsToggle {
            Layout.fillWidth: true
            label: "Dangerous auto-approve"
            description: "Approve each exact device action automatically instead of prompting."
            checked: root.dangerousAutoApprove
            enabled: root.backend && !root.backend.busy
            foreground: root.foreground
            accent: checked ? OmaPilotPalette.urgent : root.accent
            fontFamily: root.fontFamily
            onClicked: root.dangerousAutoApproveRequested(!root.dangerousAutoApprove)
          }

          Text {
            Layout.fillWidth: true
            visible: root.dangerousAutoApprove
            text: "Approval prompts are skipped. Commands may read, change, or delete device data and use the network."
            color: OmaPilotPalette.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          CompactSettingsToggle {
            Layout.fillWidth: true
            label: "Desktop context"
            description: "Attach the active window, open apps, workspaces, and playing media on send."
            checked: root.desktopContextEnabled
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: root.desktopContextRequested(!root.desktopContextEnabled)
          }

          Text {
            Layout.fillWidth: true
            text: "Global hotkeys"
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            Layout.fillWidth: true
            text: "Install a clearly marked OmaPilot block in ~/.config/hypr/bindings.lua. Nothing is changed until you choose Install, and existing shortcut chords are preserved."
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.md

            CompactSettingsButton {
              Layout.fillWidth: true
              text: root.hotkeyBusy ? "Updating hotkeys…" : "Install global hotkeys"
              tooltipText: "Add OmaPilot shortcuts without replacing existing shortcut chords"
              foreground: root.foreground
              background: root.background
              accent: root.accent
              active: true
              bordered: true
              focusable: true
              enabled: root.backend && !root.hotkeyBusy
              Accessible.name: tooltipText
              onClicked: root.hotkeyInstallRequested()
            }

            CompactSettingsButton {
              text: "Remove"
              tooltipText: "Remove only the hotkey block managed by OmaPilot"
              foreground: root.foreground
              background: root.background
              bordered: true
              focusable: true
              enabled: root.backend && !root.hotkeyBusy
              Accessible.name: tooltipText
              onClicked: root.hotkeyRemoveRequested()
            }
          }

          Text {
            Layout.fillWidth: true
            visible: root.hotkeyMessage !== ""
            text: root.hotkeyMessage
            color: root.hotkeyMessage.toLowerCase().indexOf("fail") >= 0
              || root.hotkeyMessage.toLowerCase().indexOf("refus") >= 0
              ? OmaPilotPalette.urgent : root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          Text {
            Layout.fillWidth: true
            text: "Search provider"
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Dropdown {
            id: webHandoffProviderPicker
            Layout.fillWidth: true
            showLabel: false
            options: Protocol.webHandoffProviderOptions()
            value: Protocol.normalizedWebHandoffProvider(root.webHandoffProvider) || "duckduckgo"
            enabled: root.backend && !root.backend.busy
            foreground: root.foreground
            background: root.background
            Accessible.name: "Search provider"
            onChanged: function(value) { root.webHandoffProviderRequested(value) }
          }

          Text {
            Layout.fillWidth: true
            text: "For current-information requests, OmaPilot can open the question in this site. AI sites also get a paste-ready copy in case they cannot prefill it. The answer stays in the browser and is not read back into this conversation."
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          Text {
            Layout.fillWidth: true
            text: "Browser context"
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.md

            Rectangle {
              Layout.preferredWidth: Style.space(8)
              Layout.preferredHeight: Style.space(8)
              radius: width / 2
              color: root.browserCompanionConnected ? root.accent
                : (root.browserCompanion.phase === "failed" ? OmaPilotPalette.urgent : root.mutedForeground)
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
                    : "Enable browser context to install the relay and bundled extension, then restart the browser.")
                color: root.mutedForeground
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
            color: OmaPilotPalette.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.md

            CompactSettingsButton {
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

            CompactSettingsButton {
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

          CompactSettingsButton {
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
              color: root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.md

              CompactSettingsButton {
                Layout.fillWidth: true
                text: "Open Chromium extensions"
                foreground: root.foreground
                background: root.background
                bordered: true
                focusable: true
                Accessible.name: text
                onClicked: root.browserCompanionOpenSettingsRequested("chromium")
              }

              CompactSettingsButton {
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
              color: root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.md

              CompactSettingsButton {
                Layout.fillWidth: true
                text: "Open Firefox debugging"
                foreground: root.foreground
                background: root.background
                bordered: true
                focusable: true
                Accessible.name: text
                onClicked: root.browserCompanionOpenSettingsRequested("firefox")
              }

              CompactSettingsButton {
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

            CompactSettingsButton {
              Layout.fillWidth: true
              iconText: "󰆴"
              text: root.browserRemoveConfirmation ? "Confirm removal" : "Remove browser context"
              tooltipText: root.browserRemoveConfirmation
                ? "Confirm removal of the native relay, browser registrations, and extension flags"
                : "Remove the native relay, browser registrations, and extension flags"
              foreground: root.foreground
              background: root.background
              accent: OmaPilotPalette.urgent
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

            CompactSettingsButton {
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
        }
      }

      Flickable {
        id: actionsScroll
        anchors.fill: parent
        visible: root.selectedTab === "actions"
        contentWidth: width
        contentHeight: actionsContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ColumnLayout {
          id: actionsContent
          width: actionsScroll.width
          spacing: Style.spacing.xxl

          Text {
            Layout.fillWidth: true
            text: "Prompts shown on an empty conversation. Up to five."
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          QuickActionEditor {
            id: quickActionEditor
            Layout.fillWidth: true
            actions: root.quickActions
            foreground: root.foreground
            background: root.background
            accent: root.accent
            fontFamily: root.fontFamily
            onActionsEdited: function(actions) { root.quickActionsEdited(actions) }
          }
        }
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(37)

      Rectangle {
        anchors.fill: parent
        color: root.background
        Accessible.ignored: true
      }

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Style.spacing.hairline
        color: OmaPilotPalette.normalBorder(root.foreground)
        Accessible.ignored: true
      }

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Style.spacing.panelPadding
        anchors.rightMargin: Style.spacing.panelPadding
        spacing: Style.space(5)

        Text {
          Layout.fillWidth: true
          text: "OmaPilot / settings / " + root.selectedTab
          color: root.mutedForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          Accessible.role: Accessible.StaticText
          Accessible.name: text
        }

        BorderSurface {
          Layout.preferredWidth: settingsFooterKey.implicitWidth + Style.spacing.xl
          Layout.preferredHeight: settingsFooterKey.implicitHeight + Style.spacing.xxs
          color: OmaPilotPalette.normalFill(root.foreground)
          borderSpec: Border.flat(
            OmaPilotPalette.normalBorder(root.foreground), Style.normalBorderWidth)
          radius: Style.cornerRadius

          Text {
            id: settingsFooterKey
            anchors.centerIn: parent
            text: "esc"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          text: "back"
          color: root.mutedForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
