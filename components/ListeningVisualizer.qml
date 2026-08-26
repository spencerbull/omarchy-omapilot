import QtQuick
import qs.Commons
import "Protocol.js" as Protocol

Item {
  id: root

  property string visualizer: "kitt"
  property color accent: Color.accent
  property real level: 0.5
  property bool levelMetered: false
  property real intensity: 1
  property bool motionEnabled: true
  readonly property string selectedVisualizer:
    Protocol.normalizedVoiceVisualizer(visualizer) || "kitt"
  readonly property bool rendererLoaded: visualizerLoader.status === Loader.Ready
  readonly property bool voiceBoxActive: selectedVisualizer === "kitt"
  readonly property real rendererPhase: rendererLoaded && visualizerLoader.item !== null
    && visualizerLoader.item.phase !== undefined ? Number(visualizerLoader.item.phase) : 0

  Loader {
    id: visualizerLoader
    anchors.fill: parent
    active: root.visible
    sourceComponent: root.selectedVisualizer === "bumper" ? bumperComponent
      : (root.selectedVisualizer === "segments" ? segmentsComponent
        : (root.selectedVisualizer === "spectrum" ? spectrumComponent
          : (root.selectedVisualizer === "dots" ? dotsComponent
            : waveComponent)))
  }

  Component {
    id: waveComponent
    VoiceWave {
      accent: root.accent
      level: root.level
      levelMetered: root.levelMetered
      intensity: root.intensity
      motionEnabled: root.motionEnabled
      motionStyle: "listening"
      visualizer: root.selectedVisualizer
    }
  }

  Component {
    id: bumperComponent
    BumperVisualizer {
      accent: root.accent
      level: root.level
      levelMetered: root.levelMetered
      intensity: root.intensity
      motionEnabled: root.motionEnabled
    }
  }

  Component {
    id: segmentsComponent
    SegmentVisualizer {
      accent: root.accent
      level: root.level
      levelMetered: root.levelMetered
      intensity: root.intensity
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
      motionEnabled: root.motionEnabled
    }
  }
}
