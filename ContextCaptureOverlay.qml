import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "components" as OmaPilot

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property string requestId: ""
  property var target: ({})
  readonly property var targetScreen: {
    var name = String(target && target.monitor && target.monitor.name || "")
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name || "") === name) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }
  property bool pressed: false
  property bool dragging: false
  property real startX: 0
  property real startY: 0
  property real currentX: 0
  property real currentY: 0
  property real pointerX: 0
  property real pointerY: 0
  readonly property real selectionX: Math.min(startX, currentX)
  readonly property real selectionY: Math.min(startY, currentY)
  readonly property real selectionWidth: Math.abs(currentX - startX)
  readonly property real selectionHeight: Math.abs(currentY - startY)
  readonly property bool validRegion: selectionWidth >= 12 && selectionHeight >= 12

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(String(payloadJson || "{}")) || {} } catch (error) { payload = {} }
    requestId = String(payload.id || "")
    target = payload.target && typeof payload.target === "object" ? payload.target : {}
    resetGesture()
    opened = requestId !== ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    var cancelId = opened ? requestId : ""
    opened = false
    resetGesture()
    if (cancelId !== "") OmaPilot.OmaPilotStore.cancelContextCapture(cancelId)
    if (cancelId !== "") requestId = ""
  }

  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "io.github.spencerbull.omapilot")
  }

  function resetGesture() {
    pressed = false
    dragging = false
    startX = 0
    startY = 0
    currentX = 0
    currentY = 0
  }

  function commit(mouseX, mouseY) {
    if (!pressed) return
    pressed = false
    pointerX = mouseX
    pointerY = mouseY
    pending.mode = dragging && validRegion ? "region" : "window"
    pending.region = pending.mode === "region" ? {
      x: Math.round(selectionX), y: Math.round(selectionY),
      width: Math.max(1, Math.round(selectionWidth)), height: Math.max(1, Math.round(selectionHeight))
    } : null
    pending.anchor = { x: Math.round(mouseX), y: Math.round(mouseY) }
    opened = false
    captureTimer.restart()
  }

  QtObject {
    id: pending
    property string mode: "window"
    property var region: null
    property var anchor: null
  }

  // Let the overlay disappear for two compositor frames before grim runs.
  Timer {
    id: captureTimer
    interval: 32
    repeat: false
    onTriggered: {
      OmaPilot.OmaPilotStore.captureContext(root.requestId, pending.mode, pending.region, pending.anchor)
      root.dismiss()
    }
  }

  PanelWindow {
    id: panel
    screen: root.targetScreen
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omapilot-context-capture"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: function(event) { root.dismiss(); event.accepted = true }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.CrossCursor
        preventStealing: true
        onPressed: function(mouse) {
          root.pressed = true
          root.dragging = false
          root.startX = mouse.x
          root.startY = mouse.y
          root.currentX = mouse.x
          root.currentY = mouse.y
          mouse.accepted = true
        }
        onPositionChanged: function(mouse) {
          root.pointerX = mouse.x
          root.pointerY = mouse.y
          if (!root.pressed) return
          root.currentX = mouse.x
          root.currentY = mouse.y
          if (!root.dragging && (Math.abs(root.currentX - root.startX) >= 8 || Math.abs(root.currentY - root.startY) >= 8))
            root.dragging = true
        }
        onReleased: function(mouse) { root.commit(mouse.x, mouse.y); mouse.accepted = true }
        onCanceled: root.resetGesture()
      }

      Rectangle {
        visible: root.dragging
        x: root.selectionX
        y: root.selectionY
        width: root.selectionWidth
        height: root.selectionHeight
        color: "transparent"
        border.color: Color.accent
        border.width: Math.max(2, Style.space(2))
        radius: Style.cornerRadius
      }

      BorderSurface {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.space(32)
        width: Math.min(parent.width - Style.space(48), hintLayout.implicitWidth + Style.spacing.xl * 2)
        height: hintLayout.implicitHeight + Style.spacing.md * 2
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Style.normalBorderWidth)
        radius: Style.cornerRadius

        ColumnLayout {
          id: hintLayout
          anchors.centerIn: parent
          spacing: Style.spacing.xxs

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Click a window beneath the cursor, or drag an exact region"
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Browsers open the DOM picker • other apps offer OCR and screenshot • Escape cancels"
            color: Qt.darker(Color.popups.text, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
