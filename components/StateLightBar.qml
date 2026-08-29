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
  property real travel: 0.08
  // Incommensurate harmonics make the light feel organic without pretending
  // to be random input or measurable progress. The cycle is deterministic,
  // but the three frequencies take a long time to visibly line up again.
  property real livingPhase: 0
  readonly property real flicker: atmosphereActive
    ? (0.50 + 0.24 * Math.sin(livingPhase)
      + 0.16 * Math.sin(livingPhase * 1.618 + 1.2)
      + 0.10 * Math.sin(livingPhase * 2.414 + 3.4)) : 0.5
  readonly property real livingDrift: drift * 0.72
    + (atmosphereActive ? 0.28 * Math.sin(livingPhase * 0.437 + 0.8) : 0)
  readonly property bool thinking: phase === "thinking"
  // Listening remains a centred breath. Thinking becomes a directional pair
  // of counter-moving blooms, reusing the same rail and satellite rather than
  // introducing a second progress indicator.
  readonly property real glowCenter: thinking
    ? 0.16 + travel * 0.68 : 0.5 + livingDrift * 0.055
  readonly property real glowSpread: thinking ? 0.072 : 0.11
  readonly property real satelliteCenter: thinking
    ? 0.84 - travel * 0.68 : 0.5 + livingDrift * 0.22
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
      travel = phase === "thinking" ? 0.08 : 0.5
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
      duration: root.thinking ? 620 : 2600
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: root; property: "tide"; to: 0.18
      duration: root.thinking ? 760 : 3400
      easing.type: Easing.InOutSine
    }
  }

  Timer {
    interval: 40
    repeat: true
    running: root.atmosphereActive
    onTriggered: {
      var pace = root.thinking ? 0.132 : 0.034
      root.livingPhase = (root.livingPhase + pace) % (Math.PI * 200)
      if (root.thinking) root.travel = (root.travel + 0.0095) % 1
    }
  }

  SequentialAnimation {
    id: driftAnimation
    running: root.atmosphereActive
    loops: Animation.Infinite
    NumberAnimation {
      target: root; property: "drift"; to: 1
      duration: root.thinking ? 1300 : 6200
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: root; property: "drift"; to: -1
      duration: root.thinking ? 1700 : 7600
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
        GradientStop { position: root.glowCenter - root.glowSpread; color: root.withAlpha(0.05) }
        GradientStop { position: root.glowCenter; color: root.withAlpha(0.88 + root.flicker * 0.12) }
        GradientStop { position: root.glowCenter + root.glowSpread; color: root.withAlpha(0.05) }
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
    brightness: 0.32 + root.tide * 0.38 + root.flicker * 0.12
    colorization: 1
    colorizationColor: root.displayedColor
    opacity: 0.48 + root.tide * 0.38
  }


  // A smaller satellite bloom slips around the main source. Its irrational
  // cadence is the bit of controlled irregularity that stops the bar reading
  // as a loading indicator.
  Item {
    id: satelliteSource
    width: parent.width * ((root.thinking ? 0.055 : 0.08) + root.flicker * 0.035)
    height: 4
    x: parent.width * root.satelliteCenter - width / 2
    anchors.verticalCenter: parent.verticalCenter
    visible: false

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.30; color: root.withAlpha(0.16) }
        GradientStop { position: 0.50; color: root.withAlpha(0.34 + root.flicker * 0.18) }
        GradientStop { position: 0.70; color: root.withAlpha(0.16) }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }
  }

  MultiEffect {
    anchors.fill: satelliteSource
    source: satelliteSource
    autoPaddingEnabled: true
    blurEnabled: true
    blur: 1
    blurMax: 24
    blurMultiplier: 1.6
    brightness: 0.2 + root.flicker * 0.18
    colorization: 1
    colorizationColor: root.displayedColor
    opacity: root.atmosphereActive ? 0.72 : 0
    Behavior on opacity {
      enabled: root.motionEnabled
      NumberAnimation { duration: 220 }
    }
  }

  onPhaseChanged: settleAtmosphere()
  onMotionEnabledChanged: settleAtmosphere()
  onAtmosphereActiveChanged: settleAtmosphere()
  Component.onCompleted: settleAtmosphere()
}
