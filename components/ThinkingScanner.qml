import QtQuick
import QtQuick.Effects
import qs.Commons

// A reversible processing light for states where OmaPilot is doing backend
// work. It is deliberately scanner-shaped rather than waveform-shaped: there
// is no audio signal to imply while a model or tool is producing a response.
Item {
  id: root

  property color accent: OmaPilotPalette.accent
  property bool active: false
  property bool motionEnabled: true
  property real intensity: 1
  property real progress: 0.5

  readonly property bool running: scannerTravel.running
  readonly property real runnerWidth: Math.max(1, width * 0.24)
  readonly property real runnerX: (width - runnerWidth) * progress

  implicitHeight: Style.space(28)
  visible: active || opacity > 0.001
  opacity: active ? intensity : 0

  function withAlpha(alpha) {
    return Qt.rgba(accent.r, accent.g, accent.b, alpha)
  }

  Behavior on opacity {
    enabled: root.motionEnabled
    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
  }

  // The short pauses at each edge make the reversal readable without feeling
  // abrupt. A full return trip takes just over two seconds: active, but calm.
  SequentialAnimation {
    id: scannerTravel
    running: root.active && root.motionEnabled
    loops: Animation.Infinite
    NumberAnimation {
      target: root; property: "progress"; from: 0; to: 1
      duration: 960; easing.type: Easing.InOutSine
    }
    PauseAnimation { duration: 70 }
    NumberAnimation {
      target: root; property: "progress"; from: 1; to: 0
      duration: 960; easing.type: Easing.InOutSine
    }
    PauseAnimation { duration: 70 }
  }

  onActiveChanged: {
    if (!active) progress = 0.5
  }
  onMotionEnabledChanged: {
    if (!motionEnabled) progress = 0.5
  }

  // A nearly transparent rail gives the moving light somewhere to live while
  // preserving the existing edge-glow language.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    y: parent.height - 2
    height: 1
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: "transparent" }
      GradientStop { position: 0.12; color: root.withAlpha(0.12) }
      GradientStop { position: 0.50; color: root.withAlpha(0.28) }
      GradientStop { position: 0.88; color: root.withAlpha(0.12) }
      GradientStop { position: 1.0; color: "transparent" }
    }
  }

  // Render a broad transparent source once, then bloom it upward from the
  // screen edge. The symmetric falloff works in both travel directions.
  Item {
    id: scannerGlowSource
    anchors.fill: parent
    visible: false

    Rectangle {
      x: root.runnerX
      y: parent.height - 10
      width: root.runnerWidth
      height: 9
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.18; color: root.withAlpha(0.12) }
        GradientStop { position: 0.36; color: root.withAlpha(0.54) }
        GradientStop { position: 0.50; color: root.withAlpha(0.96) }
        GradientStop { position: 0.64; color: root.withAlpha(0.54) }
        GradientStop { position: 0.82; color: root.withAlpha(0.12) }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }
  }

  MultiEffect {
    anchors.fill: scannerGlowSource
    source: scannerGlowSource
    autoPaddingEnabled: true
    blurEnabled: true
    blur: 1
    blurMax: 42
    blurMultiplier: 2.1
    brightness: 0.68
    colorization: 1
    colorizationColor: root.accent
    opacity: 0.94
  }

  // The bloom needs one crisp luminous core or it reads as fog instead of a
  // scanner. Keep its edges transparent so it never becomes a solid block.
  Rectangle {
    x: root.runnerX
    y: parent.height - 4
    width: root.runnerWidth
    height: 3
    radius: 1.5
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: "transparent" }
      GradientStop { position: 0.18; color: root.withAlpha(0.10) }
      GradientStop { position: 0.34; color: root.withAlpha(0.48) }
      GradientStop { position: 0.44; color: root.withAlpha(1.0) }
      GradientStop { position: 0.56; color: root.withAlpha(1.0) }
      GradientStop { position: 0.66; color: root.withAlpha(0.48) }
      GradientStop { position: 0.82; color: root.withAlpha(0.10) }
      GradientStop { position: 1.0; color: "transparent" }
    }
  }
}
