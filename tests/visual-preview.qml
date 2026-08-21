import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "components" as OmaPilot
import "components/QuickActions.js" as ActionCatalog

ShellRoot {
  id: root
  readonly property string previewState: Quickshell.env("OMAPILOT_PREVIEW_STATE") || "empty"
  readonly property bool holdOpen: Quickshell.env("OMAPILOT_PREVIEW_HOLD") === "1"
  readonly property int captureDelay: {
    const requested = Number(Quickshell.env("OMAPILOT_PREVIEW_DELAY"))
    return Number.isFinite(requested) && requested > 0 ? requested : 700
  }

  QtObject {
    id: backend
    property bool initialized: true
    property bool busy: false
    property bool canSubmit: true
    property bool providerReady: true
    property bool continuationBlocked: false
    property string continuationProvider: ""
    property bool canRetry: false
    property bool contextCaptureAvailable: true
    property bool desktopContextActive: false
    property string state: root.previewState === "waiting" ? "preparing"
      : (root.previewState === "streaming" ? "streaming"
        : (root.previewState === "error" || root.previewState === "error-details"
          ? "error" : "composing"))
    property string provider: "builtin"
    property string model: "openai-codex::gpt-5.4"
    property string transcript: ""
    property string statusMessage: root.previewState === "waiting" ? "Preparing Codex…"
      : (root.previewState === "error" || root.previewState === "error-details"
        ? "The harness stopped before completing the response." : "")
    property string question: root.previewState === "waiting"
      || root.previewState === "streaming"
      || root.previewState === "error"
      || root.previewState === "error-details"
      ? "Find the current status and summarize what matters." : ""
    property var errorDetails: ({
      title: "Request failed",
      message: "The harness stopped before completing the response.",
      code: "provider_failed",
      retryable: true
    })
    property var pendingPermission: null
    property var providers: [
      { value: "builtin", label: "Built-in (OmaPilot)", policy: { tools: "device-approval" } }
    ]
    property var modelOptions: [{ value: "openai-codex::gpt-5.4", label: "GPT-5.4 (openai-codex)" }]
    property var providerPolicy: ({ tools: "device-approval", web: "approved-command", hostReads: true })
    property var builtinAuthMethods: [
      { value: "openai-codex::oauth", label: "OpenAI (ChatGPT Plus/Pro)",
        description: "Use your OpenAI Codex subscription in OmaPilot." },
      { value: "openai::api_key", label: "OpenAI API key",
        description: "Store this credential only in OmaPilot's private configuration." },
      { value: "xai::oauth", label: "xAI (Grok/X subscription)",
        description: "Use your Anthropic subscription in OmaPilot." }
    ]
    property var customProviders: []
    property var customProviderSaved: null
    property string customProviderError: ""
    property var voxtypeOsd: ({ available: true, enabled: true, message: "" })
    property var browserCompanionStatus: ({
      phase: "ready", relayInstalled: false, setupAvailable: true,
      chromiumConnected: false, firefoxConnected: false,
      chromiumExtensionPath: "", firefoxExtensionPath: "", message: ""
    })
    property bool browserCompanionConnected: false
    property bool browserCompanionBusy: false
    property var builtinAuth: ({ phase: "idle", flowId: "", methodId: "", message: "",
      url: "", verificationUri: "", userCode: "", prompt: null })
    property bool builtinAuthBusy: false
    property var contextAttachments: root.previewState === "context" ? [{
      id: "11111111-1111-4111-8111-111111111111",
      title: "Contextual cursor article",
      origin: { appId: "chromium", windowTitle: "OmaPilot design notes" },
      previewImage: { source: Qt.resolvedUrl("assets/omapilot-mark.png") },
      representations: [
        { id: "text", kind: "text", label: "Text", preview: "The magic comes from clipping the semantic object under the cursor.", confidence: 0.92 },
        { id: "image", kind: "image", label: "Screenshot", preview: "", confidence: 1 }
      ],
      selectedRepresentationIds: ["text"]
    }] : []

    signal focusComposerRequested()

    function submit(text) { return String(text || "").trim() !== "" }
    function selectProvider(value) { provider = String(value || "") }
    function startDictation() {}
    function stopDictation() {}
    function cancel() {}
    function retryBroker() {}
    function authenticateBuiltIn(methodId) {}
    function respondBuiltInAuth(value) {}
    function cancelBuiltInAuth() {}
    function activateLink(url) {}
    function copyText(text) {}
    function beginContextCapture() {}
    function setContextRepresentation(id, mode) {
      if (contextAttachments.length > 0) contextAttachments[0].selectedRepresentationIds = String(mode).split("+")
    }
    function removeContextAttachment(id) { contextAttachments = [] }
  }

  Window {
    id: previewWindow
    width: 860
    height: root.previewState === "settings" || root.previewState === "dangerous-settings"
      || root.previewState === "actions-settings" || root.previewState === "history" ? 760
      : (root.previewState === "error-details" ? 520 : (root.previewState === "context" ? 430 : 320))
    visible: true
    color: "transparent"
    flags: Qt.FramelessWindowHint
    title: "OmaPilot Visual Preview"

    BorderSurface {
      id: previewSurface
      anchors.fill: parent
      color: Color.popups.background
      borderSpec: Border.surfaceSpec(
        "popups", "border", Color.popups.border, Math.max(1, Style.normalBorderWidth))
      radius: Style.cornerRadius

      ColumnLayout {
        visible: root.previewState === "empty" || root.previewState === "dangerous" || root.previewState === "context"
        anchors.fill: parent
        anchors.leftMargin: previewSurface.contentLeftInset + Style.spacing.popupPadding
        anchors.rightMargin: previewSurface.contentRightInset + Style.spacing.popupPadding
        anchors.topMargin: previewSurface.contentTopInset + Style.spacing.popupPadding
        anchors.bottomMargin: previewSurface.contentBottomInset + Style.spacing.popupPadding
        spacing: Style.spacing.lg

        OmaPilot.OmaPilotHeader {
          id: header
          Layout.fillWidth: true
          backend: backend
          dangerousAutoApprove: root.previewState === "dangerous"
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          fontFamily: Style.font.family
        }

        OmaPilot.Composer {
          id: composer
          Layout.fillWidth: true
          backend: backend
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          fontFamily: Style.font.family
        }

        OmaPilot.QuickActions {
          id: actions
          Layout.fillWidth: true
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          fontFamily: Style.font.family
        }
      }

      OmaPilot.SettingsView {
        id: settingsView
        visible: root.previewState === "settings"
          || root.previewState === "dangerous-settings"
          || root.previewState === "actions-settings"
        anchors.fill: parent
        anchors.leftMargin: previewSurface.contentLeftInset + Style.spacing.popupPadding
        anchors.rightMargin: previewSurface.contentRightInset + Style.spacing.popupPadding
        anchors.topMargin: previewSurface.contentTopInset + Style.spacing.popupPadding
        anchors.bottomMargin: previewSurface.contentBottomInset + Style.spacing.popupPadding
        backend: backend
        selectedTab: root.previewState === "dangerous-settings" ? "desktop"
          : (root.previewState === "actions-settings" ? "actions" : "agent")
        dangerousAutoApprove: root.previewState === "dangerous-settings"
        desktopContextEnabled: true
        quickActions: root.previewState === "actions-settings"
          ? ActionCatalog.addAction(ActionCatalog.defaultActions(true, true),
            "Research this", "Research this topic using current sources.", 42)
          : ActionCatalog.defaultActions(true, true)
        foreground: Color.popups.text
        background: Color.popups.background
        accent: Color.accent
        fontFamily: Style.font.family
      }

      OmaPilot.HistoryView {
        id: historyView
        visible: root.previewState === "history"
        anchors.fill: parent
        anchors.leftMargin: previewSurface.contentLeftInset + Style.spacing.popupPadding
        anchors.rightMargin: previewSurface.contentRightInset + Style.spacing.popupPadding
        anchors.topMargin: previewSurface.contentTopInset + Style.spacing.popupPadding
        anchors.bottomMargin: previewSurface.contentBottomInset + Style.spacing.popupPadding
        history: [
          { id: "chat-1", title: "Summarize the current window", provider: "builtin",
            model: "gpt-5.4", timestamp: "Today 14:03" },
          { id: "chat-2", title: "Draft a reply to this thread", provider: "codex",
            model: "gpt-5.4", timestamp: "Today 11:40" },
          { id: "chat-3", title: "What is playing, and should I skip it?", provider: "opencode",
            model: "", timestamp: "Yesterday 19:12" }
        ]
        foreground: Color.popups.text
        background: Color.popups.background
        accent: Color.accent
        fontFamily: Style.font.family
      }

      ColumnLayout {
        id: responsePreview
        visible: root.previewState === "waiting"
          || root.previewState === "streaming"
          || root.previewState === "error"
        anchors.fill: parent
        anchors.leftMargin: previewSurface.contentLeftInset + Style.spacing.popupPadding
        anchors.rightMargin: previewSurface.contentRightInset + Style.spacing.popupPadding
        anchors.topMargin: previewSurface.contentTopInset + Style.spacing.popupPadding
        anchors.bottomMargin: previewSurface.contentBottomInset + Style.spacing.popupPadding
        spacing: Style.spacing.lg

        OmaPilot.OmaPilotHeader {
          Layout.fillWidth: true
          backend: backend
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          fontFamily: Style.font.family
        }

        BorderSurface {
          id: responseSurface
          Layout.fillWidth: true
          Layout.fillHeight: true
          color: Style.normalFillFor(Color.popups.text, Color.accent)
          borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)
          radius: Style.cornerRadius

          OmaPilot.ResponseActivityBorder {
            anchors.fill: parent
            z: 10
            active: root.previewState === "waiting" || root.previewState === "streaming"
            motionEnabled: true
            accent: Color.accent
            radius: responseSurface.radius
          }

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.spacing.xxl
            spacing: Style.spacing.lg

            RowLayout {
              Layout.fillWidth: true

              Text {
                Layout.fillWidth: true
                text: backend.question
                color: Qt.darker(Color.popups.text, 1.35)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                text: root.previewState === "streaming" ? "Receiving response…" : backend.statusMessage
                color: Qt.darker(Color.popups.text, 1.25)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: Font.Medium
              }
            }

            OmaPilot.ErrorNotice {
              Layout.fillWidth: true
              visible: root.previewState === "error"
              message: backend.statusMessage
              foreground: Color.popups.text
              background: Color.popups.background
              accent: Color.accent
              fontFamily: Style.font.family
            }

            Text {
              Layout.fillWidth: true
              visible: root.previewState === "streaming"
              text: "I’m checking the latest available information and organizing the response…"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }

            Item { Layout.fillHeight: true }
          }
        }
      }

      OmaPilot.ErrorDetailsView {
        id: errorDetailsView
        visible: root.previewState === "error-details"
        anchors.fill: parent
        anchors.leftMargin: previewSurface.contentLeftInset + Style.spacing.popupPadding
        anchors.rightMargin: previewSurface.contentRightInset + Style.spacing.popupPadding
        anchors.topMargin: previewSurface.contentTopInset + Style.spacing.popupPadding
        anchors.bottomMargin: previewSurface.contentBottomInset + Style.spacing.popupPadding
        backend: backend
        details: backend.errorDetails
        foreground: Color.popups.text
        background: Color.popups.background
        accent: Color.accent
        fontFamily: Style.font.family
      }
    }
  }

  Timer {
    interval: root.captureDelay
    running: true
    repeat: false
    onTriggered: {
      var invalidMain = (root.previewState === "empty" || root.previewState === "dangerous" || root.previewState === "context")
        && (header.implicitHeight <= 0 || composer.implicitHeight <= 0
          || actions.implicitHeight <= 0)
      var invalidSettings = (root.previewState === "settings"
          || root.previewState === "dangerous-settings"
          || root.previewState === "actions-settings")
        && settingsView.implicitHeight <= 0
      var invalidHistory = root.previewState === "history" && historyView.width <= 0
      var invalidResponse = (root.previewState === "waiting"
          || root.previewState === "streaming" || root.previewState === "error")
        && responsePreview.implicitHeight <= 0
      var invalidErrorDetails = root.previewState === "error-details"
        && errorDetailsView.implicitHeight <= 0
      if (invalidMain || invalidSettings || invalidHistory || invalidResponse || invalidErrorDetails) {
        console.error("omapilot visual preview failed: invalid component geometry")
        Qt.quit()
        return
      }
      var output = Quickshell.env("OMAPILOT_PREVIEW_PATH")
      previewSurface.grabToImage(function(result) {
        if (!result || !result.saveToFile(output))
          console.error("omapilot visual preview failed: screenshot save")
        else console.log("OMAPILOT_PREVIEW_SAVED=" + output)
        if (!root.holdOpen) Qt.quit()
      }, Qt.size(previewSurface.width, previewSurface.height))
    }
  }
}
