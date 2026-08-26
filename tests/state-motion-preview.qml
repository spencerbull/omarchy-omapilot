import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import "components" as OmaPilot
import "components/StatePhrases.js" as StatePhrases

// A temporal comparison fixture for the active motion signatures. It keeps
// listening, thinking, and measured TTS playback on the same surface, scale,
// and accent so only their animation character changes between lanes.
ShellRoot {
  id: root

  readonly property string outputDirectory: Quickshell.env("OMAPILOT_STATE_FRAME_DIR")
  property int frameIndex: 0
  property int phraseIndex: 0
  property real lastScannerProgress: -1
  property bool sawScannerForward: false
  property bool sawScannerReverse: false
  readonly property var speakingLevels: [0.04, 0.32, 0.74, 0.18, 0.92, 0.48, 0.10, 0.66]
  property real speakingLevel: speakingLevels[0]

  component MotionLane: Item {
    id: lane
    required property string phase
    required property string title
    required property real level
    property string visualizer: "segments"
    readonly property real wavePhase: phase === "listening"
      ? listeningVisualizer.rendererPhase : wave.phase
    property alias wavePace: wave.motionPace
    property alias waveLevel: wave.level
    property alias wavePower: wave.speakingLevel
    readonly property string selectedVisualizer: listeningVisualizer.selectedVisualizer
    readonly property bool waveVisible: listeningVisualizer.visible || wave.visible
    property alias scannerProgress: scanner.progress
    property alias scannerRunning: scanner.running

    Text {
      anchors.left: parent.left
      anchors.top: parent.top
      text: lane.title
      color: "#d9e2ff"
      font.family: Style.font.family
      font.pixelSize: 18
      font.weight: Font.DemiBold
    }

    OmaPilot.ListeningVisualizer {
      id: listeningVisualizer
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: 34
      height: 92
      accent: "#8caaee"
      level: lane.level
      levelMetered: true
      intensity: 0.92
      motionEnabled: true
      visible: lane.phase === "listening"
      visualizer: lane.visualizer
    }

    OmaPilot.VoiceWave {
      id: wave
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: 34
      height: 92
      accent: "#8caaee"
      level: lane.level
      intensity: 0.92
      motionEnabled: true
      visible: lane.phase === "speaking"
      motionStyle: "speaking"
    }

    OmaPilot.ThinkingScanner {
      id: scanner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: 34
      height: 92
      accent: "#8caaee"
      active: lane.phase === "thinking"
      motionEnabled: true
    }

    OmaPilot.StateLightBar {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      phase: lane.phase === "speaking" ? "answering" : lane.phase
      accent: "#8caaee"
      urgent: "#e78284"
      motionEnabled: true
    }
  }

  Window {
    id: previewWindow
    width: 1320
    height: 680
    visible: true
    color: "#181923"
    flags: Qt.FramelessWindowHint

    Item {
      id: captureSurface
      anchors.fill: parent

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 22
        text: StatePhrases.thinkingAt(root.phraseIndex)
        color: "#aeb8d4"
        font.family: Style.font.family
        font.pixelSize: 15
      }

      MotionLane {
        id: listeningLane
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 72
        anchors.leftMargin: 120
        anchors.rightMargin: 120
        height: 150
        phase: "listening"
        level: 0.72
        title: "LISTENING  ·  measured segments"
      }

      MotionLane {
        id: thinkingLane
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: listeningLane.bottom
        anchors.topMargin: 54
        anchors.leftMargin: 120
        anchors.rightMargin: 120
        height: 150
        phase: "thinking"
        level: 0.42
        title: "THINKING  ·  luminous processing scan"
      }

      MotionLane {
        id: speakingLane
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: thinkingLane.bottom
        anchors.topMargin: 54
        anchors.leftMargin: 120
        anchors.rightMargin: 120
        height: 150
        phase: "speaking"
        level: root.speakingLevel
        title: "SPEAKING  ·  measured animated line"
      }
    }
  }

  Timer {
    interval: 2800
    running: true
    repeat: true
    onTriggered: root.phraseIndex = (root.phraseIndex + 1) % StatePhrases.thinkingCount()
  }

  Timer {
    id: captureTimer
    interval: 450
    running: true
    repeat: false
    onTriggered: {
      if (root.outputDirectory === "") {
        console.error("omapilot state motion preview failed: OMAPILOT_STATE_FRAME_DIR is required")
        Qt.quit()
        return
      }
      if (thinkingLane.waveVisible || !thinkingLane.scannerRunning) {
        console.error("omapilot state motion preview failed: thinking did not replace the voice wave with a scanner")
        Qt.quit()
        return
      }
      if (listeningLane.selectedVisualizer !== "segments") {
        console.error("omapilot state motion preview failed: listening did not load segments")
        Qt.quit()
        return
      }
      if (root.lastScannerProgress >= 0) {
        var scannerStep = thinkingLane.scannerProgress - root.lastScannerProgress
        if (scannerStep > 0.01) root.sawScannerForward = true
        if (scannerStep < -0.01) root.sawScannerReverse = true
      }
      root.lastScannerProgress = thinkingLane.scannerProgress
      if (Math.abs(speakingLane.waveLevel - root.speakingLevel) > 0.001) {
        console.error("omapilot state motion preview failed: speaking did not follow its measured lane")
        Qt.quit()
        return
      }
      if ((root.speakingLevel <= 0.05 && speakingLane.wavePower >= 0.12)
          || (root.speakingLevel >= 0.15 && root.speakingLevel <= 0.5
            && speakingLane.wavePower <= root.speakingLevel * 1.45)
          || (root.speakingLevel >= 0.9 && speakingLane.wavePower < 0.99)) {
        console.error("omapilot state motion preview failed: speaking envelope gain is too weak or unbounded")
        Qt.quit()
        return
      }
      var output = root.outputDirectory + "/state-" + String(root.frameIndex).padStart(2, "0") + ".png"
      console.log("OMAPILOT_STATE_FRAME=" + root.frameIndex
        + " listening=" + listeningLane.wavePhase.toFixed(3)
        + " scanner=" + thinkingLane.scannerProgress.toFixed(3)
        + " speaking=" + root.speakingLevel.toFixed(2)
        + " power=" + speakingLane.wavePower.toFixed(2))
      captureSurface.grabToImage(function(result) {
        if (!result || !result.saveToFile(output)) {
          console.error("omapilot state motion preview failed: could not save " + output)
          Qt.quit()
          return
        }
        root.frameIndex += 1
        if (root.frameIndex >= 8) {
          if (!root.sawScannerForward || !root.sawScannerReverse) {
            console.error("omapilot state motion preview failed: scanner did not complete a readable reversal")
            Qt.quit()
            return
          }
          console.log("OMAPILOT_STATE_MOTION_PREVIEW_OK")
          Qt.quit()
          return
        }
        root.speakingLevel = root.speakingLevels[root.frameIndex]
        captureTimer.restart()
      })
    }
  }
}
