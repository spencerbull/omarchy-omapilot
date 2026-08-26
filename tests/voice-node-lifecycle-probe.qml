import QtQuick
import Quickshell
import "components" as OmaPilot

ShellRoot {
  id: root
  property bool failed: false
  property int stage: 0
  property real frozenLevel: 0
  property real frozenTide: 0
  property real frozenDrift: 0

  function fail(message) {
    failed = true
    console.error("omapilot voice node lifecycle probe failed: " + message)
  }

  OmaPilot.VoiceNode {
    id: node
    targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    phase: "dormant"
    thinkingVisualizer: "scanner"
    motionEnabled: false
  }

  Timer {
    id: probeTimer
    interval: 180
    running: true
    repeat: true
    onTriggered: {
      if (root.stage === 0) {
        node.phase = "listening"
        node.listeningMetered = true
        node.listeningLevel = 0.68
        root.frozenLevel = node.level
        root.frozenTide = node.tide
        root.frozenDrift = node.drift
      } else if (root.stage === 1) {
        if (node.level !== root.frozenLevel || node.tide !== root.frozenTide
            || node.drift !== root.frozenDrift)
          root.fail("reduced motion changed atmosphere values while listening")
        node.phase = "thinking"
      } else if (root.stage === 2) {
        if (node.level !== root.frozenLevel || node.tide !== root.frozenTide
            || node.drift !== root.frozenDrift)
          root.fail("reduced motion changed atmosphere values across phases")
        if (node.captionMessage !== "Thinking it through…")
          root.fail("reduced motion did not hold the first thinking phrase")
        if (node.voiceWaveActive || !node.thinkingScannerActive
            || node.scannerRunning || node.scannerProgress !== 0.5
            || node.thinkingBumperActive || node.bumperRunning
            || node.thinkingPhraseRunning)
          root.fail("reduced-motion thinking did not hold a centred scanner")
        node.motionEnabled = true
        node.phase = "listening"
      } else if (root.stage === 3) {
        if (!node.voiceWaveActive || Math.abs(node.visualLevel - 0.68) > 0.001)
          root.fail("active listening did not expose the measured microphone level")
        if (node.selectedVoiceVisualizer !== "segments" || !node.listeningRendererLoaded)
          root.fail("active listening did not load the default segment visualizer")
        node.voiceVisualizer = "dots"
      } else if (root.stage === 4) {
        if (node.selectedVoiceVisualizer !== "dots" || !node.listeningRendererLoaded
            || Math.abs(node.visualLevel - 0.68) > 0.001)
          root.fail("switching the listening visualizer lost the microphone level")
        node.listeningMetered = false
        node.phase = "thinking"
      } else if (root.stage === 5) {
        if (!node.atmosphereActive || node.tide === 0.4
            || !node.scannerRunning || node.voiceWaveActive
            || !node.thinkingPhraseRunning)
          root.fail("active thinking scanner did not replace the voice waveform")
        node.status = "Waiting for tool approval…"
        if (node.captionMessage !== "Thinking it through…"
            || node.captionDetail !== node.status)
          root.fail("rotating thinking copy did not preserve actionable detail")
        node.thinkingVisualizer = "bumper"
      } else if (root.stage === 6) {
        if (node.thinkingScannerActive || node.scannerRunning
            || !node.thinkingBumperActive || !node.bumperRunning
            || node.voiceWaveActive)
          root.fail("bumper sweep did not replace the thinking scanner")
        node.phase = "error"
      } else if (root.stage === 7) {
        if (node.atmosphereActive || node.tide !== 0.4 || node.drift !== 0)
          root.fail("terminal phase left the atmosphere cycle active")
        node.phase = "answering"
        node.speaking = true
        node.playbackMetered = true
        node.playbackLevel = 0.76
      } else if (root.stage === 8) {
        if (!node.atmosphereActive || !node.voiceWaveActive
            || !node.speakingLineActive || node.listeningVisualizerActive
            || node.selectedVoiceVisualizer !== "dots"
            || node.thinkingScannerActive || node.scannerRunning
            || node.thinkingBumperActive || node.bumperRunning)
          root.fail("speaking did not activate the measured playback atmosphere")
        if (Math.abs(node.visualLevel - 0.76) > 0.001)
          root.fail("speaking did not expose the measured playback level")
        if (node.captionMessage !== "Speaking…")
          root.fail("speaking did not expose its playback caption")
        node.motionEnabled = false
        node.playbackLevel = 0.94
      } else if (root.stage === 9) {
        if (node.visualLevel !== 0.5)
          root.fail("reduced motion did not freeze measured playback animation")
        node.speaking = false
      } else if (root.stage === 10) {
        if (node.atmosphereActive || node.voiceWaveActive)
          root.fail("completed playback left its animation active")
        if (!root.failed) console.log("OMAPILOT_VOICE_NODE_LIFECYCLE_PROBE_OK")
        probeTimer.stop()
        Qt.quit()
      }
      root.stage += 1
    }
  }
}
