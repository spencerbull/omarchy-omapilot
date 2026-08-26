import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property bool active: false
  property bool motionEnabled: true
  property color accent: OmaPilotPalette.accent
  property real radius: Style.cornerRadius
  property real phase: 0
  readonly property bool running: perimeterTravel.running
  readonly property bool runnerVisible: active && motionEnabled
  readonly property real trackInset: Style.spacing.hairline
  readonly property real trackWidth: Math.max(1, width - trackInset * 2)
  readonly property real trackHeight: Math.max(1, height - trackInset * 2)
  readonly property real trackRadius: Math.max(1,
    Math.min(radius, Math.min(trackWidth, trackHeight) / 2))
  readonly property real trackPerimeter:
    2 * Math.max(0, trackWidth - 2 * trackRadius)
    + 2 * Math.max(0, trackHeight - 2 * trackRadius)
    + 2 * Math.PI * trackRadius
  readonly property real glowSpan: 0.10
  readonly property int travelDuration: 1800
  readonly property int glowBlurMax: 36

  enabled: false
  visible: runnerVisible || opacity > 0
  opacity: runnerVisible ? 1 : 0

  Behavior on opacity {
    enabled: root.motionEnabled
    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
  }

  onOpacityChanged: {
    if (opacity === 0 && !runnerVisible) phase = 0
  }
  onMotionEnabledChanged: {
    if (!motionEnabled) phase = 0
  }

  NumberAnimation {
    id: perimeterTravel
    target: root
    property: "phase"
    from: 0
    to: 1
    duration: root.travelDuration
    loops: Animation.Infinite
    running: root.runnerVisible
  }

  Shape {
    id: runnerGlowSource
    anchors.fill: parent
    anchors.margins: root.trackInset
    visible: false
    preferredRendererType: Shape.CurveRenderer

    readonly property real strokeWidth: Style.spaceReal(12)
    readonly property real effectiveSpan: Math.min(0.5,
      Math.max(strokeWidth / root.trackPerimeter, root.glowSpan))
    readonly property real dashLength:
      root.trackPerimeter * effectiveSpan / strokeWidth
    readonly property real gapLength:
      root.trackPerimeter * (1 - effectiveSpan) / strokeWidth

    ShapePath {
      strokeColor: root.accent
      strokeWidth: runnerGlowSource.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      strokeStyle: ShapePath.DashLine
      dashPattern: [runnerGlowSource.dashLength, runnerGlowSource.gapLength]
      dashOffset: (1 - root.phase) * root.trackPerimeter / runnerGlowSource.strokeWidth
      startX: root.trackRadius
      startY: 0

      PathLine { x: root.trackWidth - root.trackRadius; y: 0 }
      PathArc {
        x: root.trackWidth
        y: root.trackRadius
        radiusX: root.trackRadius
        radiusY: root.trackRadius
        direction: PathArc.Clockwise
      }
      PathLine { x: root.trackWidth; y: root.trackHeight - root.trackRadius }
      PathArc {
        x: root.trackWidth - root.trackRadius
        y: root.trackHeight
        radiusX: root.trackRadius
        radiusY: root.trackRadius
        direction: PathArc.Clockwise
      }
      PathLine { x: root.trackRadius; y: root.trackHeight }
      PathArc {
        x: 0
        y: root.trackHeight - root.trackRadius
        radiusX: root.trackRadius
        radiusY: root.trackRadius
        direction: PathArc.Clockwise
      }
      PathLine { x: 0; y: root.trackRadius }
      PathArc {
        x: root.trackRadius
        y: 0
        radiusX: root.trackRadius
        radiusY: root.trackRadius
        direction: PathArc.Clockwise
      }
    }
  }

  MultiEffect {
    id: runnerBloom
    objectName: "responseActivityBloom"
    anchors.fill: runnerGlowSource
    source: runnerGlowSource
    visible: root.visible
    // Paint only the softened source. A second crisp stroke reads as a hard
    // dash at the leading edge instead of one continuous luminous runner.
    autoPaddingEnabled: true
    blurEnabled: true
    blur: 1
    blurMax: root.glowBlurMax
    blurMultiplier: 1.1
    brightness: 0.42
    colorization: 0.8
    colorizationColor: root.accent
    opacity: 0.88
  }
}
