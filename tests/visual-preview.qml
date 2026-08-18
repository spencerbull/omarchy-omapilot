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
    property bool initialized: root.previewState !== "auth-settings"
    property bool busy: false
    property bool canSubmit: true
    property bool canRetry: root.previewState === "auth-settings"
    property bool contextCaptureAvailable: true
    property bool desktopContextActive: false
    property string state: root.previewState === "auth-settings" ? "unavailable"
      : (root.previewState === "waiting" ? "preparing"
      : (root.previewState === "streaming" ? "streaming"
        : (root.previewState === "error" || root.previewState === "error-details"
          ? "error" : "composing")))
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
    property var providers: root.previewState === "auth-settings" ? [] : [
      { value: "builtin", label: "Built-in (OmaPilot)", policy: { tools: "device-approval" } }
    ]
    property var modelOptions: root.previewState === "auth-settings" ? []
      : [{ value: "openai-codex::gpt-5.4", label: "GPT-5.4 (openai-codex)" }]
    property var providerPolicy: ({ tools: "device-approval", web: "approved-command", hostReads: true })
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
    function authenticateBuiltIn() {}
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
    height: root.previewState === "settings" || root.previewState === "auth-settings"
      || root.previewState === "dangerous-settings"
      || root.previewState === "actions-settings" ? 760
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
          || root.previewState === "auth-settings"
          || root.previewState === "dangerous-settings"
          || root.previewState === "actions-settings"
        anchors.fill: parent
        anchors.leftMargin: previewSurface.contentLeftInset + Style.spacing.popupPadding
        anchors.rightMargin: previewSurface.contentRightInset + Style.spacing.popupPadding
        anchors.topMargin: previewSurface.contentTopInset + Style.spacing.popupPadding
        anchors.bottomMargin: previewSurface.contentBottomInset + Style.spacing.popupPadding
        backend: backend
        dangerousAutoApprove: root.previewState === "dangerous-settings"
        quickActions: root.previewState === "actions-settings"
          ? ActionCatalog.addAction(ActionCatalog.defaultActions(true, true),
            "Research this", "Research this topic using current sources.", 42)
          : ActionCatalog.defaultActions(true, true)
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
          || root.previewState === "auth-settings"
          || root.previewState === "dangerous-settings"
          || root.previewState === "actions-settings")
        && settingsView.implicitHeight <= 0
      var invalidResponse = (root.previewState === "waiting"
          || root.previewState === "streaming" || root.previewState === "error")
        && responsePreview.implicitHeight <= 0
      var invalidErrorDetails = root.previewState === "error-details"
        && errorDetailsView.implicitHeight <= 0
      if (invalidMain || invalidSettings || invalidResponse || invalidErrorDetails) {
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
