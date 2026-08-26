import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string iconText: ""
  property string tooltipText: ""
  property color foreground: Color.popups.text
  property color accent: Color.accent
  property bool listening: false
  property bool levelMetered: false
  property real level: 0
  property bool motionEnabled: true
  property bool focusable: true
  property real fallbackLevel: 0.45

  readonly property real visualLevel: !motionEnabled ? 0.5
    : (levelMetered ? Math.max(0, Math.min(1, level)) : fallbackLevel)

  signal clicked()

  implicitWidth: action.size + (listening ? Style.space(44) : 0)
  implicitHeight: action.size

  SequentialAnimation {
    running: root.listening && root.visible && root.motionEnabled && !root.levelMetered
    loops: Animation.Infinite
    NumberAnimation {
      target: root
      property: "fallbackLevel"
      to: 1
      duration: 640
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: root
      property: "fallbackLevel"
      to: 0.35
      duration: 760
      easing.type: Easing.InOutSine
    }
  }

  SplitIndicator {
    anchors.fill: parent
    gap: action.size + Style.spacing.sm * 2
    accent: root.accent
    level: root.visualLevel
    visible: root.listening
  }

  PanelActionButton {
    id: action
    anchors.centerIn: parent
    iconText: root.iconText
    tooltipText: root.tooltipText
    foreground: root.listening ? root.accent : root.foreground
    focusable: root.focusable
    enabled: root.enabled
    Accessible.name: tooltipText
    onClicked: root.clicked()
  }
}
