import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Protocol.js" as Protocol

Item {
  id: root

  required property var backend
  property bool inlineMode: false
  property string draftText: ""
  property color foreground: OmaPilotPalette.popups.text
  property color background: OmaPilotPalette.popups.background
  property color accent: OmaPilotPalette.accent
  property string fontFamily: Style.font.family
  property string monoFontFamily: Style.font.family
  property bool motionEnabled: true

  signal providerChanged(string provider)
  signal modelChanged(string provider, string model)
  signal submitted()
  signal escapeRequested()
  // Routed through key events rather than Qt Shortcut. The panel is a layer
  // surface whose keyboard focus is OnDemand after a brief Exclusive prime, so
  // window activation — which Qt.WindowShortcut depends on — is not dependable.
  // Key events reach the focused editor regardless, which is why Enter and
  // Escape below have always worked.
  signal historyRequested()

  readonly property bool inputActive: inlineMode ? inlineInput.activeFocus : promptInput.activeFocus
  readonly property bool dictationTranscribing: backend && "dictationPhase" in backend
    && String(backend.dictationPhase || "") === "transcribing"
  readonly property bool showingQuestion: !inlineMode && draftText === "" && backend
    && String(backend.question || "") !== ""
    && (String(backend.answerMarkdown || "") !== "" || backend.pendingPermission !== null
      || backend.state === "complete" || backend.state === "error"
      || backend.state === "unavailable" || backend.state === "preparing"
      || backend.state === "streaming")
  property bool attachmentPopupOpen: false
  readonly property bool popupOpen: inlineProvider.popupOpen || attachmentPopupOpen

  implicitWidth: inlineMode ? Style.space(360) : Style.space(520)
  implicitHeight: inlineMode ? Style.bar.sizeHorizontal : panelComposer.implicitHeight

  function submit() {
    if (!backend || !backend.submit(draftText)) return
    draftText = ""
    submitted()
  }

  function setDraft(text) {
    draftText = String(text || "")
    Qt.callLater(function() {
      root.forceInputFocus()
      if (!root.inlineMode) promptInput.cursorPosition = promptInput.length
      else inlineInput.cursorPosition = inlineInput.length
    })
  }

  function forceInputFocus() {
    if (inlineMode) inlineInput.forceActiveFocus()
    else promptInput.forceActiveFocus()
  }

  function closePopups() {
    inlineProvider.close()
    for (var i = 0; i < attachmentRepeater.count; i++) {
      var preview = attachmentRepeater.itemAt(i)
      if (preview) preview.closePopup()
    }
    forceInputFocus()
  }

  function refreshAttachmentPopupState() {
    var anyOpen = false
    for (var i = 0; i < attachmentRepeater.count; i++) {
      var preview = attachmentRepeater.itemAt(i)
      if (preview && preview.popupOpen) anyOpen = true
    }
    attachmentPopupOpen = anyOpen
  }

  function acceptTranscript() {
    if (!backend || !backend.transcript) return
    setDraft(backend.transcript)
  }

  Connections {
    target: root.backend
    function onTranscriptChanged() { root.acceptTranscript() }
    function onFocusComposerRequested() {
      root.draftText = ""
      Qt.callLater(root.forceInputFocus)
    }
  }

  RowLayout {
    id: inlineComposer
    anchors.fill: parent
    visible: root.inlineMode
    spacing: Style.spacing.sm

    Dropdown {
      id: inlineProvider
      Layout.preferredWidth: Style.space(92)
      Layout.fillHeight: true
      showLabel: false
      rowHeight: parent.height
      options: root.backend ? root.backend.providers : []
      value: root.backend ? root.backend.provider : ""
      foreground: root.foreground
      background: root.background
      onChanged: function(value) {
        root.backend.selectProvider(value)
        root.providerChanged(value)
      }
    }

    TextField {
      id: inlineInput
      Layout.fillWidth: true
      Layout.fillHeight: true
      enabled: root.backend && !root.backend.busy && !root.backend.continuationBlocked
      text: root.draftText
      placeholderText: root.backend && root.backend.initialized
        ? "What do you want to do?"
        : "Starting…"
      foreground: root.foreground
      horizontalPadding: Style.spacing.md
      verticalPadding: Style.spacing.xxs
      Accessible.name: "OmaPilot request"
      onTextEdited: {
        root.draftText = text
      }
      onAccepted: root.submit()
      Keys.onEscapePressed: function(event) {
        if (root.backend && root.backend.busy) root.backend.cancel()
        else root.escapeRequested()
        event.accepted = true
      }
    }

    VoiceAction {
      Layout.alignment: Qt.AlignVCenter
      iconText: root.dictationTranscribing ? "󰑓" : "󰍬"
      tooltipText: root.backend && root.backend.state === "dictating" ? "Stop dictation"
        : (root.dictationTranscribing ? "Cancel transcription"
          : (root.backend && root.backend.voiceEnabled === false ? "Enable voice in Settings" : "Dictate"))
      foreground: root.foreground
      accent: root.accent
      listening: root.backend && root.backend.state === "dictating"
      transcribing: root.dictationTranscribing
      motionEnabled: root.motionEnabled
      enabled: root.backend && root.backend.providerReady && !root.backend.continuationBlocked
        && root.backend.state !== "streaming"
        && (root.backend.state !== "preparing" || root.dictationTranscribing)
      onClicked: {
        if (root.dictationTranscribing) root.backend.cancel()
        else if (root.backend.state === "dictating") root.backend.stopDictation()
        else root.backend.startDictation()
      }
    }

    PanelActionButton {
      Layout.alignment: Qt.AlignVCenter
      iconText: root.backend && root.backend.busy ? "󰓛" : "󰒊"
      tooltipText: root.backend && root.backend.busy ? "Stop response" : "Send question"
      foreground: root.foreground
      focusable: true
      bordered: true
      enabled: root.backend && (root.backend.busy || (root.backend.canSubmit && root.draftText.trim() !== ""))
      Accessible.name: tooltipText
      onClicked: {
        if (root.backend.busy) root.backend.cancel()
        else root.submit()
      }
    }
  }

  ColumnLayout {
    id: panelComposer
    anchors.left: parent.left
    anchors.right: parent.right
    visible: !root.inlineMode
    spacing: 0

    ColumnLayout {
      Layout.fillWidth: true
      Layout.topMargin: Style.spacing.lg
      Layout.bottomMargin: Style.spacing.lg
      spacing: Style.spacing.sm
      visible: attachmentRepeater.count > 0

      Repeater {
        id: attachmentRepeater
        model: root.backend && Array.isArray(root.backend.contextAttachments)
          ? root.backend.contextAttachments : []
        onItemAdded: Qt.callLater(root.refreshAttachmentPopupState)
        onItemRemoved: Qt.callLater(root.refreshAttachmentPopupState)

        ContextAttachmentPreview {
          required property var modelData
          Layout.fillWidth: true
          backend: root.backend
          attachment: modelData
          foreground: root.foreground
          background: root.background
          accent: root.accent
          fontFamily: root.fontFamily
          onPopupOpenChanged: root.refreshAttachmentPopupState()
        }
      }
    }

    Item {
      id: promptRow
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(56)
      visible: !root.backend || root.backend.pendingPermission === null

      TextArea {
        id: promptInput
        anchors {
          left: parent.left; right: promptTools.left; top: parent.top; bottom: parent.bottom
          rightMargin: Style.spacing.md
        }
        enabled: root.backend && !root.backend.continuationBlocked
          && root.backend.state !== "streaming" && root.backend.state !== "preparing"
        text: root.draftText
        placeholderText: root.showingQuestion ? String(root.backend.question)
          : (root.backend && root.backend.initialized
            ? "Ask, or name a workspace, app, or setting"
            : "Starting OmaPilot\u2026")
        placeholderTextColor: root.showingQuestion
          ? root.foreground : OmaPilotPalette.darkForeground
        color: root.foreground
        selectionColor: OmaPilotPalette.selectionFill(root.foreground)
        selectedTextColor: root.foreground
        font.family: root.monoFontFamily
        font.pixelSize: Style.font.heading
        wrapMode: TextEdit.NoWrap
        background: null
        cursorDelegate: Rectangle {
          id: blockCursor
          property bool blinkOn: true
          width: root.showingQuestion ? 0 : Style.space(8)
          height: Style.space(20)
          color: root.accent
          opacity: blinkOn ? 1 : 0

          Timer {
            interval: 500
            repeat: true
            running: promptInput.activeFocus && !root.showingQuestion && root.motionEnabled
            onTriggered: blockCursor.blinkOn = !blockCursor.blinkOn
            onRunningChanged: if (!running) blockCursor.blinkOn = true
          }
        }
        leftPadding: 0
        topPadding: Style.space(15)
        bottomPadding: Style.spacing.xxxl
        Accessible.name: "OmaPilot request"
        onTextEdited: root.draftText = text

        Keys.onPressed: function(event) {
          if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
              && !(event.modifiers & Qt.ShiftModifier)) {
            root.submit()
            event.accepted = true
          } else if (event.key === Qt.Key_H && (event.modifiers & Qt.ControlModifier)) {
            root.historyRequested()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.backend && root.backend.busy) root.backend.cancel()
            else root.escapeRequested()
            event.accepted = true
          }
        }
      }

      Row {
        id: promptTools
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.sm

        PanelActionButton {
          iconText: "󰹑"
          tooltipText: "Clip context from the desktop"
          foreground: root.foreground
          size: Style.space(30)
          bordered: true
          focusable: true
          enabled: root.backend && root.backend.contextCaptureAvailable
          Accessible.name: tooltipText
          onClicked: root.backend.beginContextCapture()
        }

        VoiceAction {
          iconText: root.dictationTranscribing ? "󰑓" : (root.backend && root.backend.busy
            && root.backend.state !== "dictating" ? "󰓛" : "󰍬")
          tooltipText: root.backend && root.backend.state === "dictating" ? "Stop dictation"
            : (root.dictationTranscribing ? "Cancel transcription"
              : (root.backend && root.backend.busy ? "Stop response" : "Dictate with Voxtype"))
          foreground: root.foreground
          accent: root.accent
          controlSize: Style.space(30)
          listening: root.backend && root.backend.state === "dictating"
          transcribing: root.dictationTranscribing
          motionEnabled: root.motionEnabled
          enabled: root.backend && root.backend.providerReady && !root.backend.continuationBlocked
          onClicked: {
            if (root.backend.busy && root.backend.state !== "dictating") root.backend.cancel()
            else if (root.backend.state === "dictating") root.backend.stopDictation()
            else root.backend.startDictation()
          }
        }

      }
    }

    ListeningVisualizer {
      id: panelListeningVisualizer
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(76)
      Layout.leftMargin: Style.spacing.lg
      Layout.rightMargin: Style.spacing.lg
      visible: root.backend && (root.backend.state === "dictating" || root.dictationTranscribing)
      visualizer: root.backend && "voiceVisualizer" in root.backend
        ? String(root.backend.voiceVisualizer || "segments") : "segments"
      accent: root.accent
      levelMetered: root.backend && "dictationMetered" in root.backend
        && root.backend.dictationMetered === true
      level: root.dictationTranscribing ? 0.58
        : (root.backend && "dictationLevel" in root.backend
          ? Number(root.backend.dictationLevel || 0) : 0)
      intensity: 0.9
      motionEnabled: root.motionEnabled
    }

    Button {
      id: retryButton
      Layout.alignment: Qt.AlignRight
      visible: root.backend && root.backend.canRetry
        && root.backend.state !== "error" && root.backend.state !== "unavailable"
      text: "Retry"
      tooltipText: "Restart the OmaPilot broker"
      foreground: root.foreground
      background: root.background
      bordered: true
      focusable: true
      Accessible.name: tooltipText
      onClicked: root.backend.retryBroker()
    }
  }
}
