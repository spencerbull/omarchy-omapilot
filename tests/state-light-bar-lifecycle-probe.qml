import QtQuick
import Quickshell
import "components" as OmaPilot

ShellRoot {
  id: root
  property bool failed: false
  property int stage: 0
  property real frozenTide: 0
  property real frozenDrift: 0

  function fail(message) {
    failed = true
    console.error("omapilot state light bar lifecycle probe failed: " + message)
  }

  OmaPilot.StateLightBar {
    id: bar
    width: 520
    phase: "listening"
    motionEnabled: true
  }

  Timer {
    id: probeTimer
    interval: 220
    running: true
    repeat: true
    onTriggered: {
      if (root.stage === 0) {
        if (!bar.visible || !bar.atmosphereActive || !bar.motionRunning)
          root.fail("listening state was not visible and animated")
        root.frozenTide = bar.tide
        bar.phase = "thinking"
      } else if (root.stage === 1) {
        if (!bar.atmosphereActive || !bar.motionRunning || bar.tide === root.frozenTide)
          root.fail("thinking state did not continue the atmosphere")
        bar.phase = "answering"
      } else if (root.stage === 2) {
        if (bar.atmosphereActive || bar.motionRunning || bar.tide !== 0.52 || bar.drift !== 0)
          root.fail("answering state did not settle")
        bar.phase = "error"
      } else if (root.stage === 3) {
        if (bar.atmosphereActive || bar.motionRunning || bar.tide !== 0.72 || bar.drift !== 0)
          root.fail("error state did not settle")
        bar.motionEnabled = false
        bar.phase = "thinking"
        root.frozenTide = bar.tide
        root.frozenDrift = bar.drift
      } else if (root.stage === 4) {
        if (bar.atmosphereActive || bar.motionRunning
            || bar.tide !== root.frozenTide || bar.drift !== root.frozenDrift)
          root.fail("reduced motion allowed atmosphere values to change")
        if (!root.failed) console.log("OMAPILOT_STATE_LIGHT_BAR_LIFECYCLE_PROBE_OK")
        probeTimer.stop()
        Qt.quit()
      }
      root.stage += 1
    }
  }
}
