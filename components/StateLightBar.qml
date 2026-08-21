import QtQuick
import QtQuick.Effects
import qs.Commons
import "StateColor.js" as StateColor

// A persistent state light for the panel.
//
// It is intentionally quieter than a progress indicator: the rail never
// disappears, listening breathes slowly, thinking has a quicker tide, and
// terminal answer/error states settle into their own colour. Nothing here
// claims measurable progress or audio amplitude.
Item {
  id: root

  // listening | thinking | answering | error
  property string phase: "listening"
  property color accent: Color.accent
  property color urgent: Color.urgent
  property bool motionEnabled: true

  readonly property color lightColor: StateColor.forPhase(accent, urgent, phase)
  property color displayedColor: lightColor
  property real tide: 0.32
  property real drift: 0
  readonly property bool atmosphereActive: motionEnabled
    && (phase === "listening" || phase === "thinking")
  readonly property bool motionRunning: tideAnimation.running || driftAnimation.running

  implicitHeight: Style.space(10)

  function withAlpha(value) {
    return Qt.rgba(displayedColor.r, displayedColor.g, displayedColor.b, value)
  }

  function settledTide() {
    if (phase === "error") return 0.72
    if (phase === "answering") return 0.52
    return 0.32
  }

  function settleAtmosphere() {
    if (!atmosphereActive) {
      tide = settledTide()
      drift = 0
    }
  }

  Behavior on displayedColor {
    enabled: root.motionEnabled
    ColorAnimation { duration: 360; easing.type: Easing.OutCubic }
  }

  SequentialAnimation {
    id: tideAnimation
    running: root.atmosphereActive
    loops: Animation.Infinite
    NumberAnimation {
      target: root; property: "tide"; to: 1
      duration: root.phase === "thinking" ? 1050 : 2400
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: root; property: "tide"; to: 0.18
      duration: root.phase === "thinking" ? 1350 : 3100
      easing.type: Easing.InOutSine
    }
  }

  SequentialAnimation {
    id: driftAnimation
    running: root.atmosphereActive
    loops: Animation.Infinite
    NumberAnimation {
      target: root; property: "drift"; to: 1
      duration: root.phase === "thinking" ? 1900 : 5200
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: root; property: "drift"; to: -1
      duration: root.phase === "thinking" ? 2400 : 6400
      easing.type: Easing.InOutSine
    }
  }

  // A low, continuous rail keeps the state light legible even at the dimmest
  // point of its breath and when motion is disabled.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: 1
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: root.withAlpha(0.035) }
      GradientStop { position: 0.18; color: root.withAlpha(0.10) }
      GradientStop { position: 0.5; color: root.withAlpha(0.27 + root.tide * 0.15) }
      GradientStop { position: 0.82; color: root.withAlpha(0.10) }
      GradientStop { position: 1.0; color: root.withAlpha(0.035) }
    }
  }

  // The wandering centre is rendered once, then bloomed. Keeping the movement
  // inside a narrow central band makes it feel atmospheric rather than busy.
  Item {
    id: glowSource
    anchors.fill: parent
    visible: false

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: 1
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.42 + root.drift * 0.055; color: root.withAlpha(0.08) }
        GradientStop { position: 0.50 + root.drift * 0.055; color: root.withAlpha(0.92) }
        GradientStop { position: 0.58 + root.drift * 0.055; color: root.withAlpha(0.08) }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }
  }

  MultiEffect {
    anchors.fill: glowSource
    source: glowSource
    autoPaddingEnabled: true
    blurEnabled: true
    blur: 0.75
    blurMax: 18
    blurMultiplier: 0.85
    brightness: 0.28 + root.tide * 0.34
    colorization: 1
    colorizationColor: root.displayedColor
    opacity: 0.42 + root.tide * 0.38
  }

  onPhaseChanged: settleAtmosphere()
  onMotionEnabledChanged: settleAtmosphere()
  onAtmosphereActiveChanged: settleAtmosphere()
  Component.onCompleted: settleAtmosphere()
}
