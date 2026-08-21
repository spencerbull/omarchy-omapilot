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
  property var quickActions: []
  property string selectedTab: "agent"
  property bool motionEnabled: true
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
  readonly property var voxtypeOsd: backend && backend.voxtypeOsd
    ? backend.voxtypeOsd : ({ available: false, enabled: true, message: "" })
  // Guarded like browserCompanion: the offscreen contract harness injects a stub
  // backend with neither property.
  readonly property var savedServers: backend && backend.customProviders
    ? backend.customProviders : []
  readonly property string brokerServerError: backend && backend.customProviderError
    ? String(backend.customProviderError) : ""
  readonly property bool browserCompanionConnected: backend ? backend.browserCompanionConnected === true : false
  readonly property bool browserCompanionBusy: backend ? backend.browserCompanionBusy === true : false
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
  readonly property bool modalInteractionActive: popupOpen
    || browserRemoveConfirmation
    || browserCompanionBusy
    || quickActionEditor.interactionActive
    || serverRemoveConfirmId !== ""
  implicitHeight: Style.space(560)
  readonly property color mutedForeground: Qt.darker(foreground, 1.45)
  Accessible.name: "OmaPilot settings"

  signal dangerousAutoApproveRequested(bool enabled)
  signal desktopContextRequested(bool enabled)
  signal providerChanged(string provider)
  signal modelChanged(string provider, string model)
  signal quickActionsEdited(var actions)
  signal browserCompanionInstallRequested()
  signal browserCompanionUninstallRequested()
  signal browserCompanionRefreshRequested()
  signal browserCompanionOpenSettingsRequested(string family)
  signal browserCompanionCopyPathRequested(string family)
  signal customProviderAddRequested(string id, string name, string baseUrl, string api, var models, string apiKey)
  signal customProviderTestRequested(string baseUrl, string apiKey)
  signal customProviderRemoveRequested(string id)
  signal voxtypeOsdRequested(bool enabled)
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
    selectedTab = next
  }

  Connections {
    target: root.backend

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
    if (restoreFocus !== false)
      Qt.callLater(function() { tabBar.forceActiveFocus() })
  }

  function forceInitialFocus() {
    if (root.authenticationRequired) selectTab("agent")
    tabBar.forceActiveFocus()
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.spacing.md

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md

      PanelActionButton {
        id: backButton
        Layout.alignment: Qt.AlignTop
        iconText: "󰁍"
        tooltipText: "Back to conversation"
        foreground: root.foreground
        focusable: true
        Accessible.name: tooltipText
        onClicked: root.dismissed()
      }

      SettingsTabs {
        id: tabBar
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        current: root.selectedTab
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        motionEnabled: root.motionEnabled
        onSelected: function(id) { root.selectTab(id) }
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

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
          spacing: Style.spacing.lg

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
                ? Color.urgent : root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            RowLayout {
              Layout.fillWidth: true
              visible: root.backend && (String(root.backend.builtinAuth.url || "") !== ""
                || String(root.backend.builtinAuth.verificationUri || "") !== "")
              spacing: Style.spacing.md

              Button {
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

              Button {
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

              Button {
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

              Button {
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

              Button {
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
          spacing: Style.spacing.lg

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
            color: Qt.darker(root.foreground, 1.55)
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
                  Layout.preferredWidth: 2
                  Layout.preferredHeight: Style.space(28)
                  radius: 1
                  color: liveModels > 0 ? root.accent : Qt.darker(root.foreground, 1.8)
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
                    color: Qt.darker(root.foreground, 1.5)
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
                    color: liveModels > 0 ? Qt.darker(root.foreground, 1.5) : root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Button {
                  text: "Edit"
                  foreground: Qt.darker(root.foreground, 1.3)
                  background: root.background
                  bordered: true
                  focusable: true
                  onClicked: root.editServer(modelData)
                }

                Button {
                  text: root.serverRemoveConfirmId === modelData.id ? "Confirm removal" : "Remove"
                  foreground: root.serverRemoveConfirmId === modelData.id ? Color.urgent : Qt.darker(root.foreground, 1.3)
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
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            Layout.fillWidth: true
            visible: root.serverFormNotice !== "" && root.brokerServerError === "" && !root.serverFormExpanded
            text: root.serverFormNotice
            color: Qt.darker(root.foreground, 1.35)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Button {
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

            Button {
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
              color: Qt.darker(root.foreground, 1.35)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            Toggle {
              enabled: !root.serverSavePending
              checked: root.serverDraftResponses
              label: "Use the /responses API"
              description: "Turn off for servers that only implement /chat/completions."
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              Accessible.name: label
              onClicked: root.serverDraftResponses = !root.serverDraftResponses
            }

            Text {
              Layout.fillWidth: true
              wrapMode: Text.Wrap
              visible: root.serverFormError !== "" || root.brokerServerError !== ""
              text: root.serverFormError !== "" ? root.serverFormError : root.brokerServerError
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Button {
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
          spacing: Style.spacing.lg

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

          Toggle {
            Layout.fillWidth: true
            label: "Desktop context"
            description: "Attach the active window, open apps, workspaces, and playing media on send."
            checked: root.desktopContextEnabled
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            Accessible.name: label
            onClicked: root.desktopContextRequested(!root.desktopContextEnabled)
          }

          Toggle {
            Layout.fillWidth: true
            visible: root.voxtypeOsd.available
            label: "Voxtype on-screen display"
            description: "Off leaves OmaPilot's glow as the only recording indicator. Restarts the Voxtype daemon."
            checked: root.voxtypeOsd.enabled
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            Accessible.name: label
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
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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
              color: root.mutedForeground
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
              color: root.mutedForeground
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
          spacing: Style.spacing.lg

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
  }
}
