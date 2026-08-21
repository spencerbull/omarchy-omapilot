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
        node.motionEnabled = true
        node.phase = "thinking"
      } else if (root.stage === 3) {
        if (!node.atmosphereActive || node.tide === 0.4)
          root.fail("active thinking atmosphere did not start")
        node.phase = "error"
      } else if (root.stage === 4) {
        if (node.atmosphereActive || node.tide !== 0.4 || node.drift !== 0)
          root.fail("terminal phase left the atmosphere cycle active")
        if (!root.failed) console.log("OMAPILOT_VOICE_NODE_LIFECYCLE_PROBE_OK")
        probeTimer.stop()
        Qt.quit()
      }
      root.stage += 1
    }
  }
}
