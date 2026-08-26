import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string iconText: ""
  property string tooltipText: ""
  property color foreground: OmaPilotPalette.popups.text
  property color accent: OmaPilotPalette.accent
  property bool listening: false
  property bool transcribing: false
  property bool motionEnabled: true
  property bool focusable: true
  property real controlSize: Math.max(Style.space(22), Style.font.icon + Style.spacing.sm * 2)
  readonly property bool labeled: listening || transcribing

  signal clicked()

  implicitWidth: action.width
  implicitHeight: action.height

  ParallelAnimation {
    running: root.listening && root.visible && root.motionEnabled
    loops: Animation.Infinite
    ScaleAnimator {
      target: pulse
      from: 1
      to: 1.08
      duration: 1600
      easing.type: Easing.OutCubic
    }
    OpacityAnimator {
      target: pulse
      from: 0.5
      to: 0
      duration: 1600
      easing.type: Easing.OutCubic
    }
  }

  Rectangle {
    id: pulse
    anchors.fill: action
    anchors.margins: -Math.max(1, Style.spaceReal(1))
    visible: root.listening && root.motionEnabled
    color: "transparent"
    border.width: Math.max(1, Style.spaceReal(1))
    border.color: OmaPilotPalette.alpha(root.accent, 0.75)
    opacity: 0
  }

  Button {
    id: action
    anchors.centerIn: parent
    width: root.labeled ? implicitWidth : root.controlSize
    height: root.labeled ? Math.max(root.controlSize, implicitHeight) : root.controlSize
    text: root.listening ? "listening" : (root.transcribing ? "transcribing" : "")
    iconText: root.iconText
    iconSpinning: root.transcribing && root.motionEnabled
    tooltipText: root.tooltipText
    foreground: root.listening || root.transcribing ? root.accent : root.foreground
    background: root.listening || root.transcribing
      ? OmaPilotPalette.selectedFill(root.accent) : "transparent"
    accent: root.accent
    bordered: true
    fontSize: Style.font.caption
    iconSize: Style.font.icon
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.xxs
    tooltipBackground: OmaPilotPalette.tooltip.background
    tooltipForeground: OmaPilotPalette.tooltip.text
    tooltipBorder: OmaPilotPalette.tooltip.border
    focusable: root.focusable
    enabled: root.enabled
    Accessible.name: tooltipText
    onClicked: root.clicked()
  }
}
