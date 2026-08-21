import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "components" as Quickchat
import "components/internal" as QuickchatInternal
import "components/Presentation.js" as Presentation
import "components/Protocol.js" as Protocol
import "components/QuickActions.js" as ActionCatalog

Panel {
  id: root
  moduleName: "io.github.spencerbull.quickchat"
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
  readonly property string quickActionsJson: settings
    && typeof settings.quickActionsJson === "string" ? settings.quickActionsJson : ""
  readonly property var quickActionItems: ActionCatalog.actionsFromSettings(
    quickActionsJson,
    settings ? settings.showSummarizeAction === true : false,
    settings ? settings.showWorkInAppAction === true : false)
  // Floored just under the resting composer so an empty panel hugs its content.
  // The card grows from here: the answer area carries its own minimum once a
  // response exists, and quick actions add their row only when there are any.
  readonly property real minimumContentHeight: Style.space(120)
  readonly property real comfortableCardHeight: popup.availableCardHeight > 0
    ? Math.min(Style.space(720), Math.max(Style.space(320), popup.availableCardHeight * 0.82))
    : Style.space(720)
  readonly property real activeNaturalHeight: viewMode === "settings" || viewMode === "history"
    ? Math.max(minimumContentHeight, comfortableCardHeight - popup.verticalContentInset)
    : (viewMode === "error" ? errorView.implicitHeight : chatView.implicitHeight)
  readonly property var responsePhase: Presentation.responsePhase(
    Quickchat.QuickchatStore.state,
    Quickchat.QuickchatStore.answerMarkdown !== "" || Quickchat.QuickchatStore.images.length > 0)
  // True whenever the response area is presenting a failure, which is the one
  // state that used to be announced three times over.
  readonly property bool failureVisible: Quickchat.QuickchatStore.state === "error"
    || Quickchat.QuickchatStore.state === "unavailable"
  // The panel speaks the same state language as the ambient surfaces: working
  // is one hue, a delivered answer another, failure the theme's urgent role.
  readonly property string statePhase: failureVisible ? "error"
    : (responseActivityActive ? "thinking"
      : (Quickchat.QuickchatStore.answerMarkdown !== "" ? "answering" : "listening"))
  readonly property bool responseActivityActive:
    Quickchat.QuickchatStore.state === "preparing"
    || Quickchat.QuickchatStore.state === "streaming"
  readonly property bool panelWindowActive: panelFocus.Window.window
    ? panelFocus.Window.window.active : false
  readonly property bool modalInteractionActive: composer.popupOpen
    || Quickchat.QuickchatStore.pendingPermission !== null
    || root.previewSource !== ""
    || (root.viewMode === "settings" && settingsView.modalInteractionActive)
    || (root.viewMode === "history" && historyView.modalInteractionActive)
  readonly property bool workInAppActionAvailable:
    ActionCatalog.promptFor(root.quickActionItems, "work-in-app") !== ""

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
    if (prompt === "" || root.viewMode !== "chat" || Quickchat.QuickchatStore.busy) return
    composer.setDraft(prompt)
  }

  function open() {
    openedFromHotkey = false
    showChat(false)
    setCenterHoverRevealSuppressed(false)
    Quickchat.QuickchatStore.latchDesktopContext()
    root.controller.show()
    Qt.callLater(function() { composer.forceInputFocus() })
  }

  function openFromHotkey() {
    openedFromHotkey = true
    showChat(false)
    Quickchat.QuickchatStore.latchDesktopContext()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) root.setCenterHoverRevealSuppressed(true)
      composer.forceInputFocus()
    })
  }

  function openHistory() {
    settingsView.closePopups(false)
    viewMode = "history"
    Quickchat.QuickchatStore.latchDesktopContext()
    root.controller.show()
    Quickchat.QuickchatStore.requestHistory()
    Qt.callLater(function() { historyView.forceInitialFocus() })
  }

  function openSettings() {
    viewMode = "settings"
    Quickchat.QuickchatStore.requestCustomProviders()
    Quickchat.QuickchatStore.requestVoxtypeOsd()
    Quickchat.QuickchatStore.requestBrowserCompanionStatus()
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
    Quickchat.QuickchatStore.clearContextAttachments()
    Quickchat.QuickchatStore.clearDesktopContextLatch()
    root.controller.hide()
    if (hostWidget) Qt.callLater(function() {
      if (typeof hostWidget.restoreFocus === "function") hostWidget.restoreFocus()
      else hostWidget.forceActiveFocus()
    })
  }

  function closeForExternalHandoff() {
    setCenterHoverRevealSuppressed(false)
    previewSource = ""
    Quickchat.QuickchatStore.clearDesktopContextLatch()
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

  onSettingsChanged: Quickchat.QuickchatStore.configure(settings)
  Component.onCompleted: Quickchat.QuickchatStore.configure(settings)
  onOpenedChanged: {
    if (opened) {
      Quickchat.QuickchatStore.configure(settings)
      if (viewMode === "history") {
        Quickchat.QuickchatStore.requestHistory()
        Qt.callLater(function() { historyView.forceInitialFocus() })
      } else if (viewMode === "settings") {
        Qt.callLater(function() { settingsView.forceInitialFocus() })
      } else if (viewMode === "error") {
        Qt.callLater(function() { errorView.forceInitialFocus() })
      } else Qt.callLater(function() { composer.forceInputFocus() })
    } else {
      Quickchat.QuickchatStore.clearDesktopContextLatch()
    }
  }

  Connections {
    target: Quickchat.QuickchatStore
    function onHerdrContinued() { root.closeForExternalHandoff() }
    function onContextOverlayRequested(payload) {
      var hostShell = root.bar && root.bar.shell ? root.bar.shell : null
      if (!hostShell || typeof hostShell.summon !== "function") {
        Quickchat.QuickchatStore.toastRequested("Context capture is unavailable in this shell")
        return
      }
      root.closeForExternalHandoff()
      if (!hostShell.summon(root.moduleName, payload))
        Quickchat.QuickchatStore.toastRequested("Context capture overlay could not be opened")
    }
    function onContextBrowserPickerRequested() { root.closeForExternalHandoff() }
  }

  Shortcut {
    enabled: root.opened
    sequence: "Escape"
    onActivated: {
      var action = Presentation.escapeAction(root.viewMode, composer.popupOpen,
        settingsView.popupOpen, root.previewSource !== "", Quickchat.QuickchatStore.busy)
      if (action === "close-composer-popup") composer.closePopups()
      else if (action === "close-settings-popup") settingsView.closePopups()
      else if (action === "close-preview") root.previewSource = ""
      else if (action === "show-chat") root.showChat()
      else if (action === "cancel") Quickchat.QuickchatStore.cancel()
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
    // 640 was sized for the old layout, whose header carried identity on its
    // own line. The redesign puts harness, model, approval posture, and the lane
    // hints in one row, and at 640 the model name was the first thing elided —
    // exactly the part worth reading.
    contentWidth: popup.fittedContentWidth(Style.space(760))
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
      focus: true
      Keys.onPressed: function(event) { panelKeyboardNavigation.handleKey(event) }

      QuickchatInternal.PanelKeyboardNavigation {
        id: panelKeyboardNavigation
        focusRoot: panelFocus
        activeFocusItem: panelFocus.Window.window
          ? panelFocus.Window.window.activeFocusItem : null
        panelActive: root.opened && root.panelWindowActive
        modalInteractionActive: root.modalInteractionActive
        workInAppShortcutEnabled: root.viewMode === "chat"
          && root.workInAppActionAvailable
          && !Quickchat.QuickchatStore.busy
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

      ColumnLayout {
        id: chatView
        anchors.fill: parent
        visible: root.viewMode === "chat"
        spacing: Style.spacing.lg

        // The request is the hero and sits at the top. The old panel opened with
        // a logo, a tagline, and a gear, then buried the input under the answer;
        // that is app chrome. What the user came to do goes first.
        Quickchat.Composer {
          id: composer
          Layout.fillWidth: true
          backend: Quickchat.QuickchatStore
          foreground: root.foreground
          background: root.surface
          accent: root.accent
          fontFamily: root.fontFamily
          onSubmitted: answerScroll.resetForNewTurn()
          onHistoryRequested: root.viewMode === "history" ? root.showChat() : root.openHistory()
          onEscapeRequested: root.close()
        }
        // The answer, unboxed. It used to live in a filled, bordered card with a
        // runner travelling its perimeter — a window inside a window. Now it sits
        // directly on the panel under one edge-lit seam, the same seam the answer
        // curtain uses, so the typed and the spoken paths present identically.
        Item {
          id: answerCard
          readonly property bool contentVisible: Quickchat.QuickchatStore.question !== ""
            || Quickchat.QuickchatStore.answerMarkdown !== ""
            || Quickchat.QuickchatStore.state === "error"
            || Quickchat.QuickchatStore.state === "unavailable"
          Layout.fillWidth: true
          Layout.minimumHeight: contentVisible ? Style.space(120) : stateLightBar.implicitHeight
          Layout.preferredHeight: implicitHeight
          implicitHeight: contentVisible
            ? answerLayout.implicitHeight + Style.spacing.xl
            : stateLightBar.implicitHeight

          // One persistent seam carries the entire panel's state. It remains a
          // quiet accent while composing, gathers pace while working, and
          // settles into the answer or error hue without becoming a progress bar.
          Quickchat.StateLightBar {
            id: stateLightBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            phase: root.statePhase
            accent: root.accent
            urgent: Color.urgent
            motionEnabled: root.motionEnabled && root.opened
          }

          ColumnLayout {
            id: answerLayout
            visible: answerCard.contentVisible
            anchors.fill: parent
            anchors.topMargin: Style.spacing.xl
            spacing: Style.spacing.lg

            RowLayout {
              Layout.fillWidth: true
              visible: Quickchat.QuickchatStore.question !== "" || root.responsePhase.label !== ""

              Text {
                Layout.fillWidth: true
                text: Quickchat.QuickchatStore.question
                color: Qt.darker(root.foreground, 1.35)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                Accessible.role: Accessible.StaticText
                Accessible.name: text
              }

              Item {
                id: responseStatusSlot
                Layout.alignment: Qt.AlignVCenter
                Layout.minimumWidth: Style.space(140)
                Layout.preferredWidth: Math.min(Style.space(220),
                  Math.max(Layout.minimumWidth, answerLayout.width * 0.38))
                Layout.maximumWidth: Style.space(220)
                Layout.preferredHeight: Math.max(activityStatus.implicitHeight,
                  responseState.implicitHeight)

                // Keep one screen-aware status slot for every response phase.
                // Status copy and phase changes can no longer resize the
                // question column while a response is arriving.
                Text {
                  id: activityStatus
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width
                  text: Quickchat.QuickchatStore.statusMessage !== ""
                    ? Quickchat.QuickchatStore.statusMessage
                    : (Quickchat.QuickchatStore.state === "streaming" ? "Receiving response…"
                      : "Waiting for " + Protocol.providerLabel(Quickchat.QuickchatStore.provider) + "…")
                  visible: root.responseActivityActive
                  color: Qt.darker(root.foreground, 1.25)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Medium
                  horizontalAlignment: Text.AlignRight
                  elide: Text.ElideRight
                  maximumLineCount: 1
                  Accessible.role: Accessible.StaticText
                  Accessible.name: text
                }

                Text {
                  id: responseState
                  // The error notice below already names the failure in full, so
                  // a shouty UNAVAILABLE chip beside the question is the same
                  // information a third time.
                  readonly property bool phaseVisible: text !== ""
                    && !root.responseActivityActive && !root.failureVisible
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.responsePhase.label
                  visible: phaseVisible || opacity > 0
                  opacity: phaseVisible ? 1 : 0
                  color: root.responsePhase.tone === "urgent" ? Color.urgent
                    : (root.responsePhase.tone === "muted" ? Color.muted : root.accent)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1
                  Accessible.role: Accessible.StaticText
                  Accessible.name: text

                  Behavior on opacity {
                    enabled: root.motionEnabled
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                  }
                }
              }
            }

            BorderSurface {
              id: permissionCard
              Layout.fillWidth: true
              implicitHeight: permissionContent.implicitHeight + contentTopInset + contentBottomInset + Style.spacing.xl * 2
              visible: Quickchat.QuickchatStore.pendingPermission !== null
              color: Style.normalFillFor(root.foreground, root.accent)
              borderSpec: Border.controlSpec("focus", root.foreground, root.accent)
              radius: Style.cornerRadius

              QuickchatInternal.PermissionFocusGuard {
                permissionId: Quickchat.QuickchatStore.pendingPermission
                  ? String(Quickchat.QuickchatStore.pendingPermission.id || "") : ""
                defaultTarget: denyPermission.visible ? denyPermission : permissionChoices.itemAt(0)
              }

              ColumnLayout {
                id: permissionContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.spacing.xl
                spacing: Style.spacing.md

                Text {
                  Layout.fillWidth: true
                  text: Quickchat.QuickchatStore.pendingPermission
                    ? "Approval required: " + Quickchat.QuickchatStore.pendingPermission.title : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  wrapMode: Text.Wrap
                }

                Text {
                  Layout.fillWidth: true
                  text: "Review the exact request and choose how long this agent may retain the approval."
                  color: Qt.darker(root.foreground, 1.45)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                }

                Flickable {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Math.min(permissionDetail.implicitHeight, Style.space(140))
                  contentWidth: width
                  contentHeight: permissionDetail.implicitHeight
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  interactive: contentHeight > height

                  TextEdit {
                    id: permissionDetail
                    width: parent.width
                    text: Quickchat.QuickchatStore.pendingPermission
                      ? Quickchat.QuickchatStore.pendingPermission.detail : ""
                    color: Qt.darker(root.foreground, 1.25)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
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
                    visible: Quickchat.QuickchatStore.hasPermissionDecision("reject_once")
                    onClicked: Quickchat.QuickchatStore.respondPermission(
                      "reject_once", Quickchat.QuickchatStore.permissionChoiceId("reject_once"))
                  }

                  Repeater {
                    id: permissionChoices
                    model: Quickchat.QuickchatStore.permissionOptionsWithoutDenyOnce()
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
                      onClicked: Quickchat.QuickchatStore.respondPermission(modelData.decision, modelData.id)
                    }
                  }
                }
              }
            }

            Item {
              id: responseViewport
              Layout.fillWidth: true
              Layout.minimumHeight: Style.space(48)
              Layout.preferredHeight: Presentation.responseViewportHeight(
                answerContent.implicitHeight, Style.space(48), Style.space(420))

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
                  spacing: Style.spacing.xl

                  Quickchat.ErrorNotice {
                    width: parent.width
                    visible: Quickchat.QuickchatStore.state === "error"
                      || Quickchat.QuickchatStore.state === "unavailable"
                    message: Quickchat.QuickchatStore.statusMessage
                    foreground: root.foreground
                    background: root.surface
                    accent: root.accent
                    fontFamily: root.fontFamily
                    onDetailsRequested: root.openErrorDetails()
                  }

                  // Recovery sits with the explanation instead of orphaned under
                  // the composer.
                  Button {
                    visible: Quickchat.QuickchatStore.canRetry
                    text: "Retry"
                    tooltipText: "Restart the OmaPilot broker"
                    foreground: root.foreground
                    background: root.surface
                    accent: root.accent
                    bordered: true
                    focusable: true
                    Accessible.name: tooltipText
                    onClicked: Quickchat.QuickchatStore.retryBroker()
                  }

                  Text {
                    visible: Quickchat.QuickchatStore.statusMessage !== ""
                      && !root.responseActivityActive
                      && Quickchat.QuickchatStore.state !== "error"
                      && Quickchat.QuickchatStore.state !== "unavailable"
                    width: parent.width
                    text: Quickchat.QuickchatStore.statusMessage
                    color: root.responsePhase.tone === "urgent"
                      ? Color.urgent : Qt.darker(root.foreground, 1.35)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                  }

                  Quickchat.MarkdownView {
                    id: markdownAnswer
                    width: parent.width
                    visible: Quickchat.QuickchatStore.answerMarkdown !== "" || Quickchat.QuickchatStore.images.length > 0
                    markdown: Quickchat.QuickchatStore.answerMarkdown
                    images: Quickchat.QuickchatStore.images
                    foreground: root.foreground
                    background: root.surface
                    accent: root.accent
                    fontFamily: root.fontFamily
                    onVisibleChanged: {
                      firstTokenReveal.stop()
                      opacity = visible && root.motionEnabled ? 0 : 1
                      if (visible && root.motionEnabled) firstTokenReveal.restart()
                    }
                    onLinkActivated: function(url) { Quickchat.QuickchatStore.activateLink(url) }
                    onImageLoadRequested: function(image) { Quickchat.QuickchatStore.requestImage(image) }
                    onImagePreviewRequested: function(source, alt) {
                      root.previewSource = source
                      root.previewAlt = alt
                    }
                    onCopyRequested: function(text) { Quickchat.QuickchatStore.copyText(text) }

                    NumberAnimation {
                      id: firstTokenReveal
                      target: markdownAnswer
                      property: "opacity"
                      to: 1
                      duration: 160
                      easing.type: Easing.OutCubic
                    }
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

            // Borderless and quiet. These are follow-ups to an answer, not
            // primary controls, and three outlined buttons under every response
            // was the loudest thing in the old panel.
            RowLayout {
              Layout.fillWidth: true
              visible: Quickchat.QuickchatStore.answerMarkdown !== ""
                || Quickchat.QuickchatStore.currentChatId !== ""
              spacing: Style.spacing.md

              PanelActionButton {
                iconText: "󰆏"
                tooltipText: "Copy answer"
                foreground: Qt.darker(root.foreground, 1.4)
                focusable: true
                enabled: Quickchat.QuickchatStore.answerMarkdown !== ""
                Accessible.name: tooltipText
                onClicked: Quickchat.QuickchatStore.copyText(Quickchat.QuickchatStore.answerMarkdown)
              }

              Item { Layout.fillWidth: true }

              Button {
                text: "New chat"
                foreground: Qt.darker(root.foreground, 1.4)
                background: root.surface
                bordered: false
                focusable: true
                onClicked: Quickchat.QuickchatStore.newChat()
              }

              Button {
                text: "Continue in Herdr"
                tooltipText: "Continue in Herdr with the native harness permissions"
                visible: Quickchat.QuickchatStore.currentChatId !== ""
                foreground: Qt.darker(root.foreground, 1.4)
                background: root.surface
                accent: root.accent
                bordered: false
                focusable: true
                onClicked: Quickchat.QuickchatStore.continueInHerdr()
              }
            }
          }
        }

        Quickchat.QuickActions {
          id: quickActions
          Layout.fillWidth: true
          visible: Quickchat.QuickchatStore.question === ""
            && Quickchat.QuickchatStore.answerMarkdown === ""
            && !Quickchat.QuickchatStore.busy
            && quickActions.actions.length > 0
          actions: root.quickActionItems
          foreground: root.foreground
          background: root.surface
          accent: root.accent
          fontFamily: root.fontFamily
          workInAppShortcutText: "Ctrl+Shift+A"
          onActionRequested: function(actionId, prompt) { composer.setDraft(prompt) }
        }

        // One hint row carries everything the removed chrome used to: which
        // harness answered, the permission posture, and how to reach the lanes
        // that no longer have buttons. Affordances are discoverable in one
        // place instead of scattered across a header, a toolbar, and a gear.
        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.spacing.xs
          spacing: Style.spacing.md

          // Provenance keeps its natural width so the harness name is never the
          // thing that gets elided; the key hints absorb the slack instead.
          Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: {
              var who = Protocol.providerLabel(Quickchat.QuickchatStore.provider)
              if (Quickchat.QuickchatStore.model !== "")
                who += " \u00b7 " + Quickchat.QuickchatStore.model
              return who
            }
            color: Qt.darker(root.foreground, 1.35)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          // Only the dangerous posture is worth stating. Announcing the safe
          // default on every frame is noise, and it was crowding the row badly
          // enough to elide the harness name.
          Text {
            visible: root.dangerousAutoApprove
            Layout.maximumWidth: implicitWidth
            elide: Text.ElideRight
            text: Presentation.permissionNotice(root.dangerousAutoApprove)
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          // Keep the global settings binding and focused-panel history binding
          // visible and clickable. "Enter send" is omitted because text fields
          // already establish that convention.
          // Without this the auto-approve warning butts straight against the
          // first key hint and the two read as one sentence.
          Text {
            visible: root.dangerousAutoApprove
            text: "\u00b7"
            color: Qt.darker(root.foreground, 1.9)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            spacing: Style.spacing.md

            Repeater {
              model: [
                { label: "Super+Alt+P settings", lane: "settings" },
                { label: "Ctrl+H history", lane: "history" }
              ]

              delegate: Row {
                required property var modelData
                required property int index
                spacing: Style.spacing.md

                Text {
                  visible: index > 0
                  text: "\u00b7"
                  color: Qt.darker(root.foreground, 1.9)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  id: hintLabel
                  readonly property var laneData: parent.modelData
                  text: laneData.label
                  color: hint.hovered ? root.accent : Qt.darker(root.foreground, 1.2)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.underline: hint.hovered
                  Accessible.role: Accessible.Button
                  Accessible.name: "Open " + hintLabel.laneData.lane

                Behavior on color {
                  enabled: root.motionEnabled
                  ColorAnimation { duration: 120 }
                }

                HoverHandler {
                  id: hint
                  cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                  onTapped: {
                    if (root.viewMode === hintLabel.laneData.lane) root.showChat()
                    else if (hintLabel.laneData.lane === "settings") root.openSettings()
                    else root.openHistory()
                  }
                }
                }
              }
            }
          }
        }
      }

      Quickchat.SettingsView {
        id: settingsView
        anchors.fill: parent
        visible: root.viewMode === "settings"
        backend: Quickchat.QuickchatStore
        dangerousAutoApprove: root.dangerousAutoApprove
        desktopContextEnabled: settings
          && String(settings.desktopContext || "On") !== "Off"
        quickActions: root.quickActionItems
        motionEnabled: root.motionEnabled
        foreground: root.foreground
        background: root.surface
        accent: root.accent
        fontFamily: root.fontFamily
        onDangerousAutoApproveRequested: function(enabled) {
          root.persistSettings({ dangerousAutoApprove: enabled === true })
        }
        onDesktopContextRequested: function(enabled) {
          root.persistSettings({ desktopContext: enabled === true ? "On" : "Off" })
        }
        onProviderChanged: function(provider) { root.selectProvider(provider) }
        onModelChanged: function(provider, model) {
          var values = {}; values[root.providerModelKey(provider)] = model; root.persistSettings(values)
        }
        onQuickActionsEdited: function(actions) { root.setQuickActions(actions) }
        onBrowserCompanionInstallRequested: Quickchat.QuickchatStore.installBrowserCompanion()
        onBrowserCompanionUninstallRequested: Quickchat.QuickchatStore.uninstallBrowserCompanion()
        onBrowserCompanionRefreshRequested: Quickchat.QuickchatStore.requestBrowserCompanionStatus()
        onBrowserCompanionOpenSettingsRequested: function(family) { Quickchat.QuickchatStore.openBrowserCompanionSettings(family) }
        onBrowserCompanionCopyPathRequested: function(family) { Quickchat.QuickchatStore.copyBrowserCompanionPath(family) }
        onCustomProviderAddRequested: function(id, name, baseUrl, api, models, apiKey) {
          Quickchat.QuickchatStore.addCustomProvider(id, name, baseUrl, api, models, apiKey)
        }
        onCustomProviderTestRequested: function(baseUrl, apiKey) {
          Quickchat.QuickchatStore.testCustomProvider(baseUrl, apiKey)
        }
        onVoxtypeOsdRequested: function(enabled) {
          Quickchat.QuickchatStore.setVoxtypeOsd(enabled)
        }
        onCustomProviderRemoveRequested: function(id) {
          Quickchat.QuickchatStore.removeCustomProvider(id)
        }
        onDismissed: root.showChat()
      }

      Quickchat.ErrorDetailsView {
        id: errorView
        anchors.fill: parent
        visible: root.viewMode === "error"
        backend: Quickchat.QuickchatStore
        details: Quickchat.QuickchatStore.errorDetails
        foreground: root.foreground
        background: root.surface
        accent: root.accent
        fontFamily: root.fontFamily
        onAuthenticationRequested: root.openSettings()
        onDismissed: root.showChat()
      }

      Quickchat.HistoryView {
        id: historyView
        anchors.fill: parent
        visible: root.viewMode === "history"
        history: Quickchat.QuickchatStore.history
        motionEnabled: root.motionEnabled
        foreground: root.foreground
        background: root.surface
        accent: root.accent
        fontFamily: root.fontFamily
        onChatSelected: function(chat) {
          Quickchat.QuickchatStore.loadChat(chat)
          answerScroll.showFromStart()
          root.showChat()
        }
        onDeleteRequested: function(chatId) { Quickchat.QuickchatStore.deleteHistory(chatId) }
        onClearRequested: Quickchat.QuickchatStore.clearHistory()
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
