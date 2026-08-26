import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons

// The active voice visualizer along the bottom edge.
//
// This file owns the animated line used for listening and AI speech. Missing
// telemetry falls back to an authored envelope.
//
// Two earlier shapes were rejected for concrete reasons:
//
//   * scrolling a static path and masking the ends was cheap, but the mask could
//     not stay aligned with a blur-padded effect rect, which clipped the ribbon
//     into a hard vertical edge;
//   * rebuilding ~170 points every frame at 60fps cost ~25% of a core for
//     decoration.
//
// So the taper is baked into the geometry — no mask, nothing to misalign, and
// autoPadding is free to grow for the bloom — while the phase advances on a
// timer rather than a per-frame binding. Three layers at different frequencies
// and drift directions keep it from ever repeating exactly.
Item {
  id: root

  property color accent: OmaPilotPalette.accent
  property real level: 0.5          // 0..1, swells the ribbon
  property real intensity: 1        // overall opacity multiplier
  property bool compact: false
  property bool motionEnabled: true
  // listening | thinking | speaking. This changes character, not just speed.
  property string motionStyle: "listening"
  readonly property bool listening: motionStyle === "listening"
  readonly property bool thinking: motionStyle === "thinking"
  readonly property bool speaking: motionStyle === "speaking"
  readonly property real boundedLevel: Math.max(0, Math.min(1, level))
  // Provider output is commonly mastered well below full scale, which made a
  // truthful raw envelope read as barely moving. Keep the first 2.5% as a
  // silence/noise gate, then apply perceptual gain so ordinary syllables use
  // more of the available height while loud peaks remain bounded.
  readonly property real speakingLevel: boundedLevel <= 0.025 ? 0
    : Math.min(1, Math.pow((boundedLevel - 0.025) / 0.975, 0.62) * 1.18)
  // A calm standing wave while listening; a much faster travelling signal
  // while thinking. The larger ratio is intentional: the previous 28% pace
  // difference was technically present but visually indistinguishable.
  readonly property real motionPace: thinking ? 0.084 : (speaking ? 0.033 : 0.022)
  readonly property real frequencyScale: thinking ? 1.48 : (speaking ? 1.16 : 0.92)

  readonly property var layers: [
    { frequency: 1.3, drift:  1.00, weight: 1.00, thickness: 3.0, amplitude: 1.00 },
    { frequency: 2.1, drift: -0.62, weight: 0.74, thickness: 2.2, amplitude: 0.78 },
    { frequency: 3.4, drift:  0.41, weight: 0.52, thickness: 1.6, amplitude: 0.55 }
  ]
  readonly property int samples: compact ? 24 : 44

  property real phase: 0
  property real livingPhase: 0

  // A 30fps timer keeps both renderers responsive without rebuilding their
  // geometry every render frame.
  Timer {
    interval: 33
    repeat: true
    running: root.motionEnabled && root.visible
    onTriggered: {
      var variation = 1 + 0.18 * Math.sin(root.livingPhase * 0.73)
        + 0.08 * Math.sin(root.livingPhase * 1.91 + 0.7)
      var step = root.speaking ? root.motionPace : root.motionPace * variation
      root.phase = (root.phase + step) % (Math.PI * 200)
      root.livingPhase = (root.livingPhase + (root.thinking ? 0.029 : 0.013)) % (Math.PI * 200)
    }
  }

  function wavePoints(layer) {
    var points = []
    var w = root.width
    var h = root.height
    if (w <= 0 || h <= 0) return points
    var mid = h * 0.5
    var levelScale = root.speaking ? 0.025 + root.speakingLevel * 1.1
      : 0.3 + root.boundedLevel * 0.7
    var peak = mid * 0.86 * layer.amplitude * levelScale
    for (var i = 0; i <= root.samples; i++) {
      var t = i / root.samples
      // Raised-cosine envelope: zero at both ends, full in the middle. Baked in,
      // so the ribbon disperses instead of terminating — and because it lives in
      // the geometry there is no mask to fall out of alignment.
      var envelope = 0.5 - 0.5 * Math.cos(2 * Math.PI * t)
      var frequency = layer.frequency * root.frequencyScale
      var wave
      if (root.thinking) {
        // Directional phase makes the whole ribbon flow left-to-right. A tight
        // travelling knot and softer wake make the work state readable at a
        // glance without implying measurable completion.
        wave = Math.sin(t * Math.PI * 2 * frequency - root.phase * layer.drift * 1.55)
          + 0.34 * Math.sin(t * Math.PI * 2 * frequency * 1.9 - root.phase * layer.drift * 2.15)
          + 0.14 * Math.sin(t * Math.PI * 2 * frequency * 0.72
            - root.phase * layer.drift * 0.82 + root.livingPhase)
        var travel = (root.phase * 0.095) % 1
        var knot = Math.exp(-Math.pow((t - (0.10 + travel * 0.80)) / 0.095, 2))
        var wake = Math.exp(-Math.pow((t - (0.04 + travel * 0.72)) / 0.18, 2))
        wave += knot * 0.78 * Math.sin(root.phase * 2.15 + t * 12)
          + wake * 0.18 * Math.sin(root.phase * 1.2 + t * 7)
      } else if (root.speaking) {
        // Playback keeps a readable travelling carrier, but its height follows
        // the measured TTS envelope. Silence falls flat; syllables lift it.
        wave = Math.sin(t * Math.PI * 2 * frequency - root.phase * layer.drift * 0.92)
          + 0.28 * Math.sin(t * Math.PI * 2 * frequency * 2.05
            - root.phase * layer.drift * 1.34 + root.livingPhase * 0.4)
          + 0.10 * Math.sin(t * Math.PI * 2 * frequency * 0.72
            + root.phase * layer.drift * 0.36)
      } else {
        // Listening stays centred: phase bends a standing set of harmonics
        // instead of pushing them laterally, while VoiceNode supplies the slow
        // inhale/exhale in amplitude.
        var bend = Math.sin(root.phase * 0.62)
        wave = Math.sin(t * Math.PI * 2 * frequency + bend * layer.drift * 0.62)
          + 0.32 * Math.sin(t * Math.PI * 2 * frequency * 2.15 - bend * layer.drift * 0.48)
          + 0.12 * Math.sin(t * Math.PI * 2 * frequency * 0.618
            + bend * layer.drift * 0.27 + root.livingPhase)
      }
      points.push(Qt.point(t * w, mid + wave * peak * envelope * 0.74))
    }
    return points
  }

  Item {
    id: waves
    anchors.fill: parent
    visible: false

    Repeater {
      model: root.layers

      Shape {
        required property var modelData
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: modelData.weight

        ShapePath {
          strokeColor: root.accent
          strokeWidth: Math.max(1.2, Style.spaceReal(modelData.thickness))
          fillColor: "transparent"
          capStyle: ShapePath.RoundCap
          joinStyle: ShapePath.RoundJoin

          PathPolyline {
            path: root.phase >= 0 && root.width > 0 && root.height > 0
              ? root.wavePoints(modelData) : []
          }
        }
      }
    }
  }

  // autoPadding on: the bloom needs room to spread past the item bounds, and
  // denying it is exactly what produced the hard edge.
  MultiEffect {
    anchors.fill: waves
    source: waves
    autoPaddingEnabled: true
    blurEnabled: true
    blur: 1
    blurMax: 26
    blurMultiplier: 1.0
    brightness: 0.75
    colorization: 1
    colorizationColor: root.accent
    opacity: root.intensity
  }

  // The bloom alone is atmosphere without a subject: over a light window it
  // washes out entirely. This crisp pass gives the ribbon a readable edge so the
  // motion is legible rather than merely sensed.
  ShaderEffectSource {
    anchors.fill: waves
    sourceItem: waves
    hideSource: false
    opacity: root.intensity * 0.7
  }
}
