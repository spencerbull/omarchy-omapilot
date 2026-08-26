import QtQuick
import qs.Commons
import "Protocol.js" as Protocol

Item {
  id: root

  property string visualizer: "segments"
  property color accent: OmaPilotPalette.accent
  property real level: 0.5
  property bool levelMetered: false
  property real intensity: 1
  property bool compact: false
  property bool motionEnabled: true
  readonly property string selectedVisualizer:
    Protocol.normalizedVoiceVisualizer(visualizer) || "segments"
  readonly property bool rendererLoaded: visualizerLoader.status === Loader.Ready
  readonly property real rendererPhase: rendererLoaded && visualizerLoader.item !== null
    && visualizerLoader.item.phase !== undefined ? Number(visualizerLoader.item.phase) : 0

  Loader {
    id: visualizerLoader
    anchors.fill: parent
    active: root.visible
    sourceComponent: root.selectedVisualizer === "segments" ? segmentsComponent
      : (root.selectedVisualizer === "spectrum" ? spectrumComponent
        : (root.selectedVisualizer === "dots" ? dotsComponent : waveComponent))
  }

  Component {
    id: waveComponent
    VoiceWave {
      accent: root.accent
      level: root.level
      intensity: root.intensity
      compact: root.compact
      motionEnabled: root.motionEnabled
      motionStyle: "listening"
    }
  }

  Component {
    id: segmentsComponent
    SegmentVisualizer {
      accent: root.accent
      level: root.level
      levelMetered: root.levelMetered
      intensity: root.intensity
      compact: root.compact
      motionEnabled: root.motionEnabled
    }
  }

  Component {
    id: spectrumComponent
    SpectrumVisualizer {
      accent: root.accent
      level: root.level
      levelMetered: root.levelMetered
      intensity: root.intensity
      compact: root.compact
      motionEnabled: root.motionEnabled
    }
  }

  Component {
    id: dotsComponent
    DotFieldVisualizer {
      accent: root.accent
      level: root.level
      levelMetered: root.levelMetered
      intensity: root.intensity
      compact: root.compact
      motionEnabled: root.motionEnabled
    }
  }
}
