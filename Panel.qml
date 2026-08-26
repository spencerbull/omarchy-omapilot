import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "components" as OmaPilot
import "components/internal" as OmaPilotInternal
import "components/Presentation.js" as Presentation
import "components/Protocol.js" as Protocol
import "components/QuickActions.js" as ActionCatalog
import "components/StatePhrases.js" as StatePhrases

Panel {
  id: root
  moduleName: "io.github.spencerbull.omapilot"
  ipcTarget: moduleName
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property bool openedFromHotkey: false
  property string viewMode: "chat"
  property string previewSource: ""
  property string previewAlt: ""
  // Quattro and Qt 6.11 currently expose no system reduced-motion preference.
  // Keep motion injectable and limit every local transition to a finite reveal.
  property bool motionEnabled: true

  readonly property color foreground: bar ? bar.foreground : Color.popups.text
  readonly property color surface: Color.popups.background
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool dangerousAutoApprove: settings
    && settings.dangerousAutoApprove === true
  readonly property string webHandoffProvider: settings
    && Protocol.normalizedWebHandoffProvider(settings.webHandoffProvider)
    ? Protocol.normalizedWebHandoffProvider(settings.webHandoffProvider) : "duckduckgo"
  readonly property bool voiceEnabled: settings && settings.voiceEnabled === true
  readonly property string voiceVisualizer: settings
    && Protocol.normalizedVoiceVisualizer(settings.voiceVisualizer)
    ? Protocol.normalizedVoiceVisualizer(settings.voiceVisualizer) : "kitt"
  readonly property string ttsProvider: settings && Protocol.normalizedTtsProvider(settings.ttsProvider)
    ? Protocol.normalizedTtsProvider(settings.ttsProvider) : "elevenlabs"
  readonly property string ttsModel: settings && typeof settings.ttsModel === "string" ? settings.ttsModel : ""
  readonly property string ttsVoice: settings && typeof settings.ttsVoice === "string" ? settings.ttsVoice : ""
  readonly property bool onboardingComplete: settings && settings.onboardingComplete === true
  readonly property var selectedTtsCatalog: Protocol.ttsProviderStatus(
    OmaPilot.OmaPilotStore.voiceStatus, root.ttsProvider)
  readonly property bool voiceSetupReady: root.voiceEnabled
    && root.selectedTtsCatalog && root.selectedTtsCatalog.available === true
  readonly property string setupStage: Presentation.setupStage(
    OmaPilot.OmaPilotStore.providerReady, root.voiceEnabled,
    root.voiceSetupReady, root.onboardingComplete)
  readonly property string quickActionsJson: settings
    && typeof settings.quickActionsJson === "string" ? settings.quickActionsJson : ""
  readonly property var quickActionItems: ActionCatalog.actionsFromSettings(
    quickActionsJson,
    settings ? settings.showSummarizeAction === true : false,
    settings ? settings.showWorkInAppAction === true : false)
  readonly property real minimumContentHeight: Style.space(130)
  readonly property real comfortableCardHeight: popup.availableCardHeight > 0
    ? Math.min(Style.space(620), Math.max(Style.space(260), popup.availableCardHeight * 0.78))
    : Style.space(620)
  readonly property real activeNaturalHeight: viewMode === "settings"
    ? Math.max(minimumContentHeight, settingsView.implicitHeight)
    : (viewMode === "history" ? Math.max(minimumContentHeight, historyView.implicitHeight)
      : (viewMode === "error" ? errorView.implicitHeight : chatView.implicitHeight))
  readonly property bool responseActivityActive:
    OmaPilot.OmaPilotStore.state === "preparing"
    || OmaPilot.OmaPilotStore.state === "streaming"
  readonly property bool footerPrimaryAvailable: !OmaPilot.OmaPilotStore.busy
    && OmaPilot.OmaPilotStore.pendingPermission === null
  property int thinkingPhraseIndex: 0
  readonly property bool genericActivityStatus: responseActivityActive
    && StatePhrases.isGenericStatus(OmaPilot.OmaPilotStore.statusMessage)
  readonly property string activityStatusText: StatePhrases.thinkingStatus(
    thinkingPhraseIndex, OmaPilot.OmaPilotStore.statusMessage)
  readonly property bool rotatingActivityStatus: root.opened
    && root.genericActivityStatus && root.motionEnabled
  readonly property bool panelWindowActive: panelFocus.Window.window
    ? panelFocus.Window.window.active : false
  readonly property bool modalInteractionActive: composer.popupOpen
    || OmaPilot.OmaPilotStore.pendingPermission !== null
    || root.previewSource !== ""
    || (root.viewMode === "settings" && settingsView.modalInteractionActive)
    || (root.viewMode === "history" && historyView.modalInteractionActive)
  readonly property bool workInAppActionAvailable:
    ActionCatalog.promptFor(root.quickActionItems, "work-in-app") !== ""

  Timer {
    id: thinkingPhraseTimer
    interval: 2800
    running: root.rotatingActivityStatus
    repeat: true
    triggeredOnStart: false
    onTriggered: root.thinkingPhraseIndex = (root.thinkingPhraseIndex + 1)
      % StatePhrases.thinkingCount()
  }

  function resetThinkingPhrase() {
    if (!responseActivityActive) thinkingPhraseIndex = 0
  }

  onGenericActivityStatusChanged: resetThinkingPhrase()
  onResponseActivityActiveChanged: resetThinkingPhrase()
  onRotatingActivityStatusChanged: {
    if (!rotatingActivityStatus) resetThinkingPhrase()
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function selectProvider(provider) {
    var selected = String(provider || "")
    if (selected === "") return
    persistSettings({ provider: selected })
  }

  function setQuickActions(actions) {
    persistSettings({ quickActionsJson: ActionCatalog.serializedActions(actions) })
  }

  function prepareWorkInAppDraft() {
    var prompt = ActionCatalog.promptFor(root.quickActionItems, "work-in-app")
    if (prompt === "" || root.viewMode !== "chat" || OmaPilot.OmaPilotStore.busy) return
    composer.setDraft(prompt)
  }

  function open() {
    openedFromHotkey = false
    showChat(false)
    setCenterHoverRevealSuppressed(false)
    OmaPilot.OmaPilotStore.latchDesktopContext()
    root.controller.show()
    Qt.callLater(function() { composer.forceInputFocus() })
  }

  function openFromHotkey() {
    openedFromHotkey = true
    showChat(false)
    OmaPilot.OmaPilotStore.latchDesktopContext()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) root.setCenterHoverRevealSuppressed(true)
      composer.forceInputFocus()
    })
  }

  function openHistory() {
    settingsView.closePopups(false)
    viewMode = "history"
    OmaPilot.OmaPilotStore.latchDesktopContext()
    root.controller.show()
    OmaPilot.OmaPilotStore.requestHistory()
    Qt.callLater(function() { historyView.forceInitialFocus() })
  }

  function openSettings(tab) {
    if (tab) settingsView.selectTab(tab)
    viewMode = "settings"
    OmaPilot.OmaPilotStore.requestCustomProviders()
    OmaPilot.OmaPilotStore.requestVoxtypeOsd()
    OmaPilot.OmaPilotStore.requestVoiceStatus()
    OmaPilot.OmaPilotStore.requestBrowserCompanionStatus()
    Qt.callLater(function() { settingsView.forceInitialFocus() })
  }

  function openErrorDetails() {
    viewMode = "error"
    Qt.callLater(function() { errorView.forceInitialFocus() })
  }

  function showChat(restoreFocus) {
    settingsView.closePopups(false)
    viewMode = "chat"
    if (restoreFocus !== false) Qt.callLater(function() { composer.forceInputFocus() })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    previewSource = ""
    OmaPilot.OmaPilotStore.clearContextAttachments()
    OmaPilot.OmaPilotStore.clearDesktopContextLatch()
    root.controller.hide()
    if (hostWidget) Qt.callLater(function() {
      if (typeof hostWidget.restoreFocus === "function") hostWidget.restoreFocus()
      else hostWidget.forceActiveFocus()
    })
  }

  function closeForExternalHandoff() {
    setCenterHoverRevealSuppressed(false)
    previewSource = ""
    OmaPilot.OmaPilotStore.clearDesktopContextLatch()
    root.controller.hide()
  }

  function toggle() {
    if (opened) close()
    else openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function providerModelKey(provider) {
    return String(provider) + "Model"
  }

  onSettingsChanged: OmaPilot.OmaPilotStore.configure(settings)
  Component.onCompleted: OmaPilot.OmaPilotStore.configure(settings)
  onOpenedChanged: {
    if (opened) {
      OmaPilot.OmaPilotStore.configure(settings)
      if (viewMode === "history") {
        OmaPilot.OmaPilotStore.requestHistory()
        Qt.callLater(function() { historyView.forceInitialFocus() })
      } else if (viewMode === "settings") {
        Qt.callLater(function() { settingsView.forceInitialFocus() })
      } else if (viewMode === "error") {
        Qt.callLater(function() { errorView.forceInitialFocus() })
      } else Qt.callLater(function() { composer.forceInputFocus() })
    } else {
      OmaPilot.OmaPilotStore.clearDesktopContextLatch()
    }
  }

  Connections {
    target: OmaPilot.OmaPilotStore
    function onHerdrContinued() { root.closeForExternalHandoff() }
    function onContextOverlayRequested(payload) {
      var hostShell = root.bar && root.bar.shell ? root.bar.shell : null
      if (!hostShell || typeof hostShell.summon !== "function") {
        OmaPilot.OmaPilotStore.toastRequested("Context capture is unavailable in this shell")
        return
      }
      root.closeForExternalHandoff()
      if (!hostShell.summon(root.moduleName, payload))
        OmaPilot.OmaPilotStore.toastRequested("Context capture overlay could not be opened")
    }
    function onContextBrowserPickerRequested() { root.closeForExternalHandoff() }
    function onHotkeyInstalled() {
      if (root.voiceSetupReady) root.persistSettings({ onboardingComplete: true })
    }
  }

  Shortcut {
    enabled: root.opened
    sequence: "Escape"
    onActivated: {
      var action = Presentation.escapeAction(root.viewMode, composer.popupOpen,
        settingsView.popupOpen, root.previewSource !== "", OmaPilot.OmaPilotStore.busy)
      if (action === "close-composer-popup") composer.closePopups()
      else if (action === "close-settings-popup") settingsView.closePopups()
      else if (action === "close-preview") root.previewSource = ""
      else if (action === "show-chat") root.showChat()
      else if (action === "cancel") OmaPilot.OmaPilotStore.cancel()
      else root.close()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: panelFocus
    padding: 0
    contentWidth: popup.fittedContentWidth(Style.space(764))
    contentHeight: Presentation.boundedPanelHeight(root.activeNaturalHeight,
      root.minimumContentHeight, root.comfortableCardHeight,
      popup.availableCardHeight, popup.verticalContentInset)

    Behavior on contentHeight {
      enabled: root.motionEnabled
      // Streaming repeatedly retargets the natural height. SmoothedAnimation
      // follows that moving target without restarting a fixed timeline for
      // every wrapped line.
      SmoothedAnimation {
        velocity: Style.spaceReal(900)
        maximumEasingTime: 120
      }
    }

    Item {
      id: panelFocus
      anchors.fill: parent
      anchors.margins: -Math.max(1, Style.space(2))
      focus: true
      Keys.onPressed: function(event) { panelKeyboardNavigation.handleKey(event) }

      OmaPilotInternal.PanelKeyboardNavigation {
        id: panelKeyboardNavigation
        focusRoot: panelFocus
        activeFocusItem: panelFocus.Window.window
          ? panelFocus.Window.window.activeFocusItem : null
        panelActive: root.opened && root.panelWindowActive
        modalInteractionActive: root.modalInteractionActive
        workInAppShortcutEnabled: root.viewMode === "chat"
          && root.workInAppActionAvailable
          && !OmaPilot.OmaPilotStore.busy
        onWorkInAppRequested: root.prepareWorkInAppDraft()
      }

      // History remains a focused-panel shortcut. Settings already has a
      // desktop-global route (Super+Alt+P), so do not create a second binding.
      Shortcut {
        sequences: ["Ctrl+H"]
        context: Qt.WindowShortcut
        enabled: root.opened && root.panelWindowActive && !root.modalInteractionActive
        onActivated: root.viewMode === "history" ? root.showChat() : root.openHistory()
      }

      Rectangle {
        anchors.fill: parent
        color: "#101114"
        border.width: 1
        border.color: "#2f3036"
        radius: 0
        Accessible.ignored: true
      }

      ColumnLayout {
        id: chatView
        anchors.fill: parent
        visible: root.viewMode === "chat"
        spacing: 0

        OmaPilot.Composer {
          id: composer
          Layout.fillWidth: true
          Layout.leftMargin: 17
          Layout.rightMargin: 17
          backend: OmaPilot.OmaPilotStore
          foreground: root.foreground
          background: root.surface
          accent: root.accent
          fontFamily: root.fontFamily
          onSubmitted: answerScroll.resetForNewTurn()
          onHistoryRequested: root.viewMode === "history" ? root.showChat() : root.openHistory()
          onEscapeRequested: root.close()
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: "#1d1e22"
          Accessible.ignored: true
        }

        OmaPilot.SetupGuide {
          id: setupGuide
          Layout.fillWidth: true
          Layout.leftMargin: 17
          Layout.rightMargin: 17
          Layout.topMargin: 14
          Layout.bottomMargin: 15
          visible: (root.setupStage === "voice" || root.setupStage === "hotkeys")
            && OmaPilot.OmaPilotStore.question === ""
            && OmaPilot.OmaPilotStore.answerMarkdown === ""
            && !OmaPilot.OmaPilotStore.busy
          stage: root.setupStage
          foreground: root.foreground
          background: root.surface
          accent: root.accent
          fontFamily: root.fontFamily
          onActionRequested: root.openSettings(root.setupStage === "voice" ? "voice" : "desktop")
        }
        Item {
          id: answerCard
          readonly property bool contentVisible: OmaPilot.OmaPilotStore.question !== ""
            || OmaPilot.OmaPilotStore.answerMarkdown !== ""
            || OmaPilot.OmaPilotStore.state === "error"
            || OmaPilot.OmaPilotStore.state === "unavailable"
          Layout.fillWidth: true
          Layout.minimumHeight: 0
          Layout.preferredHeight: implicitHeight
          implicitHeight: contentVisible
            ? answerLayout.implicitHeight + 30
            : 0

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: "#1d1e22"
            Accessible.ignored: true
          }

          ColumnLayout {
            id: answerLayout
            visible: answerCard.contentVisible
            anchors.fill: parent
            anchors.leftMargin: 17
            anchors.rightMargin: 17
            anchors.topMargin: 14
            anchors.bottomMargin: 15
            spacing: 11

            Text {
              id: activityStatus
              Layout.fillWidth: true
              visible: root.responseActivityActive
              text: root.activityStatusText
              color: "#8d8e95"
              font.family: "JetBrains Mono"
              font.pixelSize: 10
              elide: Text.ElideRight
              maximumLineCount: 1
              Accessible.role: Accessible.StaticText
              Accessible.name: text
            }

            BorderSurface {
              id: permissionCard
              Layout.fillWidth: true
              implicitHeight: permissionContent.implicitHeight
              visible: OmaPilot.OmaPilotStore.pendingPermission !== null
              color: "transparent"
              borderSpec: Border.none()
              radius: 0

              OmaPilotInternal.PermissionFocusGuard {
                permissionId: OmaPilot.OmaPilotStore.pendingPermission
                  ? String(OmaPilot.OmaPilotStore.pendingPermission.id || "") : ""
                defaultTarget: denyPermission.visible ? denyPermission : permissionChoices.itemAt(0)
              }

              ColumnLayout {
                id: permissionContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 9

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.spacing.md

                  OmaPilot.ResponseBadge {
                    responseClass: "CONFIRM"
                  }

                  Text {
                    Layout.fillWidth: true
                    text: OmaPilot.OmaPilotStore.pendingPermission
                      ? OmaPilot.OmaPilotStore.pendingPermission.title : ""
                    color: "#8d8e95"
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: "Review the exact request before it runs."
                  color: "#f0f0f2"
                  font.family: root.fontFamily
                  font.pixelSize: 15
                  wrapMode: Text.Wrap
                }

                Flickable {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Math.min(permissionDetail.implicitHeight, Style.space(100))
                  contentWidth: width
                  contentHeight: permissionDetail.implicitHeight
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  interactive: contentHeight > height

                  TextEdit {
                    id: permissionDetail
                    width: parent.width
                    text: OmaPilot.OmaPilotStore.pendingPermission
                      ? OmaPilot.OmaPilotStore.pendingPermission.detail : ""
                    color: "#d5d5da"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 11
                    wrapMode: Text.WrapAnywhere
                    textFormat: Text.PlainText
                    readOnly: true
                    selectByMouse: true
                  }
                }

                Flow {
                  Layout.fillWidth: true
                  Layout.preferredHeight: implicitHeight
                  spacing: Style.spacing.md

                  Button {
                    id: denyPermission
                    text: "Deny"
                    foreground: root.foreground
                    background: root.surface
                    bordered: true
                    focusable: true
                    visible: OmaPilot.OmaPilotStore.hasPermissionDecision("reject_once")
                    onClicked: OmaPilot.OmaPilotStore.respondPermission(
                      "reject_once", OmaPilot.OmaPilotStore.permissionChoiceId("reject_once"))
                  }

                  Repeater {
                    id: permissionChoices
                    model: OmaPilot.OmaPilotStore.permissionOptionsWithoutDenyOnce()
                    delegate: Button {
                      required property var modelData
                      id: permissionChoice
                      text: modelData.label
                      foreground: root.foreground
                      background: root.surface
                      accent: root.accent
                      active: modelData.decision === "allow_once"
                      bordered: true
                      focusable: true
                      onClicked: OmaPilot.OmaPilotStore.respondPermission(modelData.decision, modelData.id)
                    }
                  }
                }
              }
            }

            RowLayout {
              id: responseHeader
              Layout.fillWidth: true
              visible: OmaPilot.OmaPilotStore.state === "complete"
                && (OmaPilot.OmaPilotStore.answerMarkdown !== ""
                  || OmaPilot.OmaPilotStore.images.length > 0)
              spacing: 9

              OmaPilot.ResponseBadge {
                responseClass: OmaPilot.OmaPilotStore.response.class
              }

              Text {
                Layout.fillWidth: true
                text: Presentation.responseSummary(OmaPilot.OmaPilotStore.response)
                color: "#8d8e95"
                font.family: root.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
                Accessible.role: Accessible.StaticText
                Accessible.name: text
              }

              OmaPilot.ResponseAction {
                id: copyAnswerAction
                Layout.alignment: Qt.AlignVCenter
                iconText: "󰆏"
                text: "COPY"
                tooltipText: "Copy answer"
                quiet: true
                enabled: OmaPilot.OmaPilotStore.answerMarkdown !== ""
                Accessible.name: tooltipText
                onClicked: OmaPilot.OmaPilotStore.copyText(OmaPilot.OmaPilotStore.answerMarkdown)
              }
            }

            Item {
              id: responseViewport
              Layout.fillWidth: true
              Layout.minimumHeight: 1
              Layout.preferredHeight: Presentation.responseViewportHeight(
                answerContent.implicitHeight, 1, Style.space(420))

              Flickable {
                id: answerScroll
                anchors.fill: parent
                contentWidth: width
                contentHeight: answerContent.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                property bool followLatest: true
                property bool followMotionEnabled: true
                readonly property real bottomThreshold: Style.space(56)
                readonly property bool latestAvailable: contentHeight > height && !followLatest

                Behavior on contentY {
                  enabled: root.motionEnabled && answerScroll.followLatest
                    && answerScroll.followMotionEnabled
                    && !answerScroll.dragging && !answerScroll.flicking
                  SmoothedAnimation {
                    velocity: Style.spaceReal(820)
                    maximumEasingTime: 110
                  }
                }

                function maximumContentY() {
                  return Math.max(0, contentHeight - height)
                }

                function scrollToLatest() {
                  followLatest = true
                  contentY = maximumContentY()
                }

                function resetForNewTurn() {
                  followLatest = true
                  followMotionEnabled = false
                  contentY = 0
                  Qt.callLater(function() { answerScroll.followMotionEnabled = true })
                }

                function showFromStart() {
                  followLatest = false
                  followMotionEnabled = false
                  contentY = 0
                  Qt.callLater(function() { answerScroll.followMotionEnabled = true })
                }

                function followContentIfNeeded() {
                  if (!followLatest) return
                  Qt.callLater(function() {
                    if (answerScroll.followLatest) answerScroll.contentY = answerScroll.maximumContentY()
                  })
                }

                onContentHeightChanged: followContentIfNeeded()
                onHeightChanged: followContentIfNeeded()
                onContentYChanged: if (dragging || flicking)
                  followLatest = Presentation.isNearBottom(contentY, contentHeight, height, bottomThreshold)
                onMovementEnded: followLatest = Presentation.isNearBottom(
                  contentY, contentHeight, height, bottomThreshold)

                Column {
                  id: answerContent
                  width: answerScroll.width
                  spacing: 11

                  OmaPilot.ErrorNotice {
                    width: parent.width
                    visible: OmaPilot.OmaPilotStore.state === "error"
                      || OmaPilot.OmaPilotStore.state === "unavailable"
                    message: OmaPilot.OmaPilotStore.statusMessage
                    foreground: root.foreground
                    background: root.surface
                    accent: root.accent
                    fontFamily: root.fontFamily
                    onDetailsRequested: root.openErrorDetails()
                  }

                  // Recovery sits with the explanation instead of orphaned under
                  // the composer.
                  Button {
                    visible: OmaPilot.OmaPilotStore.canRetry
                    text: "Retry"
                    tooltipText: "Restart the OmaPilot broker"
                    foreground: root.foreground
                    background: root.surface
                    accent: root.accent
                    bordered: true
                    focusable: true
                    Accessible.name: tooltipText
                    onClicked: OmaPilot.OmaPilotStore.retryBroker()
                  }

                  Text {
                    visible: OmaPilot.OmaPilotStore.statusMessage !== ""
                      && !root.responseActivityActive
                      && OmaPilot.OmaPilotStore.state !== "error"
                      && OmaPilot.OmaPilotStore.state !== "unavailable"
                    width: parent.width
                    text: OmaPilot.OmaPilotStore.statusMessage
                    color: Qt.darker(root.foreground, 1.35)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                  }

                  OmaPilot.MarkdownView {
                    id: markdownAnswer
                    width: parent.width
                    visible: OmaPilot.OmaPilotStore.answerMarkdown !== "" || OmaPilot.OmaPilotStore.images.length > 0
                    markdown: OmaPilot.OmaPilotStore.answerMarkdown
                    images: OmaPilot.OmaPilotStore.images
                    foreground: "#f0f0f2"
                    background: "#101114"
                    accent: "#58d1dc"
                    fontFamily: root.fontFamily
                    onLinkActivated: function(url) { OmaPilot.OmaPilotStore.activateLink(url) }
                    onImageLoadRequested: function(image) { OmaPilot.OmaPilotStore.requestImage(image) }
                    onImagePreviewRequested: function(source, alt) {
                      root.previewSource = source
                      root.previewAlt = alt
                    }
                    onCopyRequested: function(text) { OmaPilot.OmaPilotStore.copyText(text) }
                  }

                  OmaPilot.CommandReceipt {
                    width: parent.width
                    receipt: OmaPilot.OmaPilotStore.response.receipt
                  }
                }
              }

              Button {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Style.spacing.sm
                visible: answerScroll.latestAvailable
                text: "Latest"
                tooltipText: "Jump to the newest response"
                foreground: root.foreground
                background: root.surface
                accent: root.accent
                active: true
                bordered: true
                focusable: true
                Accessible.name: tooltipText
                onClicked: answerScroll.scrollToLatest()
              }
            }

            RowLayout {
              id: sessionActions
              Layout.fillWidth: true
              visible: OmaPilot.OmaPilotStore.answerMarkdown !== ""
                || OmaPilot.OmaPilotStore.currentChatId !== ""
              spacing: 6

              Item { Layout.fillWidth: true }

              OmaPilot.ResponseAction {
                iconText: "+"
                text: "NEW CHAT"
                tooltipText: "New chat \u00b7 Super+Alt+N"
                Accessible.name: tooltipText
                onClicked: OmaPilot.OmaPilotStore.newChat()
              }

              OmaPilot.ResponseAction {
                iconText: ">"
                text: "CONTINUE IN HERDR"
                tooltipText: "Continue with native harness permissions \u00b7 Super+Alt+H"
                visible: OmaPilot.OmaPilotStore.currentChatId !== ""
                primary: true
                Accessible.name: tooltipText
                onClicked: OmaPilot.OmaPilotStore.continueInHerdr()
              }
            }
          }
        }

        OmaPilot.QuickActions {
          id: quickActions
          Layout.fillWidth: true
          Layout.leftMargin: 17
          Layout.rightMargin: 17
          Layout.topMargin: 8
          Layout.bottomMargin: 8
          visible: OmaPilot.OmaPilotStore.question === ""
            && OmaPilot.OmaPilotStore.answerMarkdown === ""
            && !OmaPilot.OmaPilotStore.busy
            && quickActions.actions.length > 0
          actions: root.quickActionItems
          foreground: root.foreground
          background: root.surface
          accent: root.accent
          fontFamily: root.fontFamily
          workInAppShortcutText: "Ctrl+Shift+A"
          onActionRequested: function(actionId, prompt) { composer.setDraft(prompt) }
        }

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 37

          Rectangle {
            anchors.fill: parent
            color: "#0c0c0f"
            Accessible.ignored: true
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: "#1d1e22"
            Accessible.ignored: true
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 17
            anchors.rightMargin: 17
            spacing: 12

            Text {
              Layout.fillWidth: true
              text: "OmaPilot"
              color: "#6f7077"
              font.family: "JetBrains Mono"
              font.pixelSize: 10
              Accessible.role: Accessible.StaticText
              Accessible.name: text
            }

            Repeater {
              model: [
                { label: "settings", lane: "settings" },
                { label: "history", lane: "history" }
              ]

              delegate: Text {
                required property var modelData
                id: footerLane
                text: modelData.label
                color: activeFocus || footerLaneHover.hovered ? "#58d1dc" : "#74757c"
                font.family: "JetBrains Mono"
                font.pixelSize: 10
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Open " + modelData.label

                HoverHandler {
                  id: footerLaneHover
                  cursorShape: Qt.PointingHandCursor
                }
                TapHandler { onTapped: footerLane.activate() }
                Keys.onReturnPressed: footerLane.activate()
                Keys.onEnterPressed: footerLane.activate()

                function activate() {
                  if (modelData.lane === "settings") root.openSettings()
                  else root.openHistory()
                }
              }
            }

            Repeater {
              model: Presentation.footerKeyHints([], root.footerPrimaryAvailable ? "↵" : "",
                root.footerPrimaryAvailable ? "run" : "", root.footerPrimaryAvailable ? "close" : "cancel")

              delegate: Row {
                required property string modelData
                readonly property var parts: modelData.split(" ")
                readonly property string keyLabel: parts.length > 0 ? parts[0] : ""
                readonly property string actionLabel: parts.slice(1).join(" ")
                spacing: 5

                Rectangle {
                  width: footerKey.implicitWidth + 10
                  height: footerKey.implicitHeight + 2
                  color: "#1b1c20"
                  border.width: 1
                  border.color: "#2b2c31"
                  radius: 0

                  Text {
                    id: footerKey
                    anchors.centerIn: parent
                    text: parent.parent.keyLabel
                    color: "#a0a1a8"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: parent.actionLabel
                  color: "#74757c"
                  font.family: "JetBrains Mono"
                  font.pixelSize: 10
                }
              }
            }
          }
        }

      }

      OmaPilot.SettingsView {
        id: settingsView
        anchors.fill: parent
        visible: root.viewMode === "settings"
        backend: OmaPilot.OmaPilotStore
        dangerousAutoApprove: root.dangerousAutoApprove
        webHandoffProvider: root.webHandoffProvider
        desktopContextEnabled: settings
          && String(settings.desktopContext || "On") !== "Off"
        voiceEnabled: root.voiceEnabled
        voiceVisualizer: root.voiceVisualizer
        ttsProvider: root.ttsProvider
        ttsModel: root.ttsModel
        ttsVoice: root.ttsVoice
        quickActions: root.quickActionItems
        motionEnabled: root.motionEnabled
        foreground: "#f0f0f2"
        background: "#101114"
        accent: "#58d1dc"
        fontFamily: "JetBrains Mono"
        onDangerousAutoApproveRequested: function(enabled) {
          root.persistSettings({ dangerousAutoApprove: enabled === true })
        }
        onDesktopContextRequested: function(enabled) {
          root.persistSettings({ desktopContext: enabled === true ? "On" : "Off" })
        }
        onWebHandoffProviderRequested: function(provider) {
          root.persistSettings({ webHandoffProvider: Protocol.normalizedWebHandoffProvider(provider) || "duckduckgo" })
        }
        onCapabilityEnabledRequested: function(capabilityId, enabled) {
          OmaPilot.OmaPilotStore.setCapabilityEnabled(capabilityId, enabled)
        }
        onCapabilityFilesRootRequested: function(path) {
          OmaPilot.OmaPilotStore.setCapabilityFilesRoot(path)
        }
        onCapabilitiesRefreshRequested: OmaPilot.OmaPilotStore.requestCapabilities()
        onProviderChanged: function(provider) { root.selectProvider(provider) }
        onModelChanged: function(provider, model) {
          var values = {}; values[root.providerModelKey(provider)] = model; root.persistSettings(values)
        }
        onQuickActionsEdited: function(actions) { root.setQuickActions(actions) }
        onBrowserCompanionInstallRequested: OmaPilot.OmaPilotStore.installBrowserCompanion()
        onBrowserCompanionUninstallRequested: OmaPilot.OmaPilotStore.uninstallBrowserCompanion()
        onBrowserCompanionRefreshRequested: OmaPilot.OmaPilotStore.requestBrowserCompanionStatus()
        onBrowserCompanionOpenSettingsRequested: function(family) { OmaPilot.OmaPilotStore.openBrowserCompanionSettings(family) }
        onBrowserCompanionCopyPathRequested: function(family) { OmaPilot.OmaPilotStore.copyBrowserCompanionPath(family) }
        onHotkeyInstallRequested: OmaPilot.OmaPilotStore.installHotkeys()
        onHotkeyRemoveRequested: OmaPilot.OmaPilotStore.removeHotkeys()
        onCustomProviderAddRequested: function(id, name, baseUrl, api, models, apiKey) {
          OmaPilot.OmaPilotStore.addCustomProvider(id, name, baseUrl, api, models, apiKey)
        }
        onCustomProviderTestRequested: function(baseUrl, apiKey) {
          OmaPilot.OmaPilotStore.testCustomProvider(baseUrl, apiKey)
        }
        onVoxtypeOsdRequested: function(enabled) {
          OmaPilot.OmaPilotStore.setVoxtypeOsd(enabled)
        }
        onVoiceEnabledRequested: function(enabled) {
          root.persistSettings({ voiceEnabled: enabled === true })
        }
        onVoiceVisualizerRequested: function(visualizer) {
          root.persistSettings({
            voiceVisualizer: Protocol.normalizedVoiceVisualizer(visualizer) || "kitt"
          })
        }
        onTtsProviderRequested: function(provider) {
          var selected = Protocol.normalizedTtsProvider(provider) || "elevenlabs"
          var catalog = Protocol.ttsProviderStatus(OmaPilot.OmaPilotStore.voiceStatus, selected)
          var model = Protocol.ttsDefaultModel(catalog)
          var voice = Protocol.ttsDefaultVoice(catalog, model)
          root.persistSettings({ ttsProvider: selected, ttsModel: model, ttsVoice: voice })
        }
        onTtsModelRequested: function(model) {
          var catalog = Protocol.ttsProviderStatus(OmaPilot.OmaPilotStore.voiceStatus, root.ttsProvider)
          var selected = String(model || "")
          var voice = root.ttsVoice
          if (!Protocol.ttsVoiceAvailable(catalog, selected, voice))
            voice = Protocol.ttsDefaultVoice(catalog, selected)
          root.persistSettings({ ttsModel: selected, ttsVoice: voice })
        }
        onTtsVoiceRequested: function(voice) {
          root.persistSettings({ ttsVoice: String(voice || "") })
        }
        onTtsKeySetRequested: function(provider, apiKey) {
          OmaPilot.OmaPilotStore.setTtsKey(provider, apiKey)
        }
        onTtsKeyClearRequested: function(provider) {
          OmaPilot.OmaPilotStore.clearTtsKey(provider)
        }
        onTtsKeyTestRequested: function(provider, apiKey) {
          OmaPilot.OmaPilotStore.testTtsKey(provider, apiKey)
        }
        onCustomProviderRemoveRequested: function(id) {
          OmaPilot.OmaPilotStore.removeCustomProvider(id)
        }
        onDismissed: root.showChat()
      }

      OmaPilot.ErrorDetailsView {
        id: errorView
        anchors.fill: parent
        visible: root.viewMode === "error"
        backend: OmaPilot.OmaPilotStore
        details: OmaPilot.OmaPilotStore.errorDetails
        foreground: root.foreground
        background: root.surface
        accent: root.accent
        fontFamily: root.fontFamily
        onAuthenticationRequested: root.openSettings()
        onDismissed: root.showChat()
      }

      OmaPilot.HistoryView {
        id: historyView
        anchors.fill: parent
        visible: root.viewMode === "history"
        history: OmaPilot.OmaPilotStore.history
        motionEnabled: root.motionEnabled
        foreground: root.foreground
        background: root.surface
        accent: root.accent
        fontFamily: root.fontFamily
        onChatSelected: function(chat) {
          OmaPilot.OmaPilotStore.loadChat(chat)
          answerScroll.showFromStart()
          root.showChat()
        }
        onDeleteRequested: function(chatId) { OmaPilot.OmaPilotStore.deleteHistory(chatId) }
        onClearRequested: OmaPilot.OmaPilotStore.clearHistory()
        onCloseRequested: {
          root.showChat()
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: root.previewSource !== ""
        z: 100
        color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.82)

        TapHandler { onTapped: root.previewSource = "" }

        BorderSurface {
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.spacing.xxl * 2, Style.space(500))
          height: Math.min(parent.height - Style.spacing.xxl * 2, Style.space(500))
          color: root.surface
          borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.normalBorderWidth))
          radius: Style.cornerRadius

          TapHandler { onTapped: function(eventPoint) { eventPoint.accepted = true } }

          Image {
            anchors.fill: parent
            anchors.margins: Style.spacing.xxl
            source: root.previewSource
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            Accessible.name: root.previewAlt
          }

          PanelActionButton {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.spacing.sm
            iconText: "󰅙"
            tooltipText: "Close image preview"
            foreground: root.foreground
            focusable: true
            Accessible.name: tooltipText
            onClicked: root.previewSource = ""
          }
        }
      }
    }
  }
}
