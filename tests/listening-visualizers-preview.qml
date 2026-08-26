import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import "components" as OmaPilot

ShellRoot {
  id: root

  readonly property string outputPath: Quickshell.env("OMAPILOT_VISUALIZER_FRAME")
  property real liveLevel: 0.72

  component VisualizerLane: Item {
    id: lane
    required property string visualizer
    required property string title
    readonly property bool rendererLoaded: renderer.rendererLoaded
    readonly property string selectedVisualizer: renderer.selectedVisualizer

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: 210
      text: lane.title
      color: "#a0a1a8"
      font.family: "JetBrains Mono"
      font.pixelSize: 14
    }

    OmaPilot.ListeningVisualizer {
      id: renderer
      anchors.left: parent.left
      anchors.leftMargin: 220
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      visualizer: lane.visualizer
      accent: "#e78284"
      level: root.liveLevel
      levelMetered: true
      intensity: 0.94
      motionEnabled: true
    }
  }

  Window {
    width: 1200
    height: 760
    visible: true
    color: "#17171b"
    flags: Qt.FramelessWindowHint

    Item {
      id: captureSurface
      anchors.fill: parent
      anchors.margins: 34

      Text {
        anchors.left: parent.left
        anchors.top: parent.top
        text: "LISTENING VISUALIZERS"
        color: "#f0f0f2"
        font.family: "JetBrains Mono"
        font.pixelSize: 16
        font.bold: true
      }

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 42
        spacing: 8

        VisualizerLane { id: kitt; width: parent.width; height: 100; visualizer: "kitt"; title: "1A  KITT VOICE BOX" }
        VisualizerLane { id: bumper; width: parent.width; height: 100; visualizer: "bumper"; title: "1B  BUMPER SWEEP" }
        VisualizerLane { id: segments; width: parent.width; height: 100; visualizer: "segments"; title: "1C  SEGMENTS ONLY" }
        VisualizerLane { id: spectrum; width: parent.width; height: 100; visualizer: "spectrum"; title: "1D  MIRRORED SPECTRUM" }
        VisualizerLane { id: dots; width: parent.width; height: 100; visualizer: "dots"; title: "1E  DOT FIELD" }
        VisualizerLane { id: line; width: parent.width; height: 100; visualizer: "line"; title: "LINE  ANIMATED LINE" }
      }
    }
  }

  Timer {
    interval: 650
    running: true
    repeat: false
    onTriggered: {
      var lanes = [kitt, bumper, segments, spectrum, dots, line]
      for (var i = 0; i < lanes.length; i++) {
        if (!lanes[i].rendererLoaded || lanes[i].selectedVisualizer !== lanes[i].visualizer) {
          console.error("omapilot visualizer preview failed: " + lanes[i].visualizer + " did not load")
          Qt.quit()
          return
        }
      }
      if (root.outputPath === "") {
        console.error("omapilot visualizer preview failed: OMAPILOT_VISUALIZER_FRAME is required")
        Qt.quit()
        return
      }
      captureSurface.grabToImage(function(result) {
        if (!result || !result.saveToFile(root.outputPath)) {
          console.error("omapilot visualizer preview failed: could not save frame")
          Qt.quit()
          return
        }
        console.log("OMAPILOT_VISUALIZER_PREVIEW_OK")
        Qt.quit()
      })
    }
  }
}
