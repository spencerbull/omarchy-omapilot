import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "components" as Quickchat

BarWidget {
  id: root
  moduleName: "io.github.spencerbull.quickchat"

  // Quattro does not currently expose free space for a bar section. Inline
  // composition is therefore opt-in-by-capability: a future host can expose
  // `availableInlineWidth` or `availableWidgetWidth`; today the safe path is
  // the icon plus anchored panel, which cannot compress the crowded clock and
  // status widgets.
  readonly property real hostInlineAllowance: {
    if (!bar) return 0
    if ("availableInlineWidth" in bar) return Number(bar.availableInlineWidth) || 0
    if ("availableWidgetWidth" in bar) return Number(bar.availableWidgetWidth) || 0
    return 0
  }
  readonly property bool canInline: !vertical && hostInlineAllowance >= Style.space(390)
  property bool inlineExpanded: false
  readonly property bool inlineActive: canInline && inlineExpanded
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property real openPanelIndicatorWidth: inlineActive ? inlineComposer.width : button.width

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root.inlineActive ? inlineComposer : button
    if ("hostWidget" in target) target.hostWidget = root
    Quickchat.QuickchatStore.configure(root.settings)
  }

  function persist(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function open() {
    inlineExpanded = false
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    inlineExpanded = false
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function openHistory() {
    if (panelLoader.item && panelLoader.item.openHistory) panelLoader.item.openHistory()
  }

  function routedWidget() {
    if (bar && typeof bar.findPanelWidget === "function") {
      var target = bar.findPanelWidget(moduleName)
      if (target) return target
    }
    return root
  }

  function routeOpen() { routedWidget().open() }
  function routeClose() { routedWidget().close() }
  function routeToggle() { routedWidget().togglePanel() }
  function routeHistory() { routedWidget().openHistory() }

  function closeForPopoutSwitch() {
    inlineExpanded = false
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function restoreFocus() {
    if (root.inlineActive) inlineComposer.forceInputFocus()
    else button.forceActiveFocus()
  }

  function activate() {
    if (root.opened) {
      root.close()
      return
    }
    Quickchat.QuickchatStore.latchDesktopContext()
    if (root.canInline) {
      root.inlineExpanded = true
      Qt.callLater(function() { inlineComposer.forceInputFocus() })
    } else root.open()
  }

  implicitWidth: inlineActive ? inlineComposer.implicitWidth : button.implicitWidth
  implicitHeight: inlineActive ? inlineComposer.implicitHeight : button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onInlineActiveChanged: injectPanel()
  onCanInlineChanged: if (!canInline) inlineExpanded = false

  Connections {
    target: Quickchat.QuickchatStore
    function onIpcOpenRequested() {
      if (root.routedWidget() === root) root.open()
    }
    function onIpcCloseRequested() {
      if (root.routedWidget() === root) root.close()
    }
    function onIpcToggleRequested() {
      if (root.routedWidget() === root) root.togglePanel()
    }
    function onIpcHistoryRequested() {
      if (root.routedWidget() === root) root.openHistory()
    }
    function onContextAttachmentAdded() {
      if (root.routedWidget() === root) root.open()
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    visible: !root.inlineActive
    bar: root.bar
    text: ""
    iconComponent: Component {
      Quickchat.OmaPilotMark {
        anchors.fill: parent
        size: Math.min(width, height)
        accent: button.active && button.useActiveColor
          ? button.activeColor : button.foreground
        active: Quickchat.QuickchatStore.busy
      }
    }
    active: root.opened || Quickchat.QuickchatStore.busy
    tooltipText: Quickchat.QuickchatStore.busy ? "OmaPilot is working" : "OmaPilot"
    Accessible.name: tooltipText

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.inlineExpanded = false
        if (panelLoader.item) panelLoader.item.openHistory()
      } else root.activate()
    }
  }

  Quickchat.Composer {
    id: inlineComposer
    anchors.fill: parent
    visible: root.inlineActive
    inlineMode: true
    backend: Quickchat.QuickchatStore
    foreground: root.bar ? root.bar.foreground : Color.bar.text
    background: Color.bar.background
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    onProviderChanged: function(provider) { root.persist({ provider: provider }) }
    onModelChanged: function(provider, model) {
      var key = provider + "Model"
      var value = {}; value[key] = model; root.persist(value)
    }
    onSubmitted: {
      root.inlineExpanded = false
      root.open()
    }
    onEscapeRequested: {
      root.inlineExpanded = false
      Quickchat.QuickchatStore.clearDesktopContextLatch()
      button.forceActiveFocus()
    }
  }
}
