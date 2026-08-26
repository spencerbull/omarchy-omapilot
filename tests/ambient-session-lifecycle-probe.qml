import QtQuick
import Quickshell
import "components" as OmaPilot

ShellRoot {
  id: root
  property bool failed: false

  function fail(message) {
    failed = true
    console.error("omapilot ambient session lifecycle probe failed: " + message)
  }

  Ambient {
    id: ambient
  }

  Timer {
    interval: 80
    running: true
    onTriggered: {
      OmaPilot.OmaPilotStore.configure({
        voiceVisualizer: "DOTS",
        thinkingVisualizer: "BUMPER"
      })
      if (OmaPilot.OmaPilotStore.voiceVisualizer !== "dots")
        root.fail("visualizer settings did not normalize a valid selection")
      if (OmaPilot.OmaPilotStore.thinkingVisualizer !== "bumper")
        root.fail("thinking visualizer settings did not normalize a valid selection")
      OmaPilot.OmaPilotStore.configure({
        voiceVisualizer: "unknown",
        thinkingVisualizer: "unknown"
      })
      if (OmaPilot.OmaPilotStore.voiceVisualizer !== "segments")
        root.fail("invalid visualizer settings did not fall back to segments")
      if (OmaPilot.OmaPilotStore.thinkingVisualizer !== "bumper")
        root.fail("invalid thinking visualizer settings did not fall back to Bumper Sweep")

      OmaPilot.OmaPilotStore.initialized = true
      OmaPilot.OmaPilotStore.dictationPhase = ""
      OmaPilot.OmaPilotStore.currentId = ""
      OmaPilot.OmaPilotStore.currentChatId = "completed-chat"
      OmaPilot.OmaPilotStore.transcript = ""
      OmaPilot.OmaPilotStore.answerMarkdown = "A completed answer"
      OmaPilot.OmaPilotStore.state = "complete"
      ambient.voiceEngaged = true
      ambient.voiceSessionActive = true

      OmaPilot.OmaPilotStore.ttsSpeakId = "failed-speech"
      OmaPilot.OmaPilotStore.ttsSpeaking = true
      OmaPilot.OmaPilotStore.applyEvent({
        type: "tts_speak_failed",
        id: "failed-speech",
        message: "Playback failed"
      })
      if (ambient.answerSpoken)
        root.fail("failed speech selected the short spoken-answer dismissal")
      if (ambient.dismissDelay < 6000)
        root.fail("failed speech did not preserve the reading-time dismissal")

      OmaPilot.OmaPilotStore.ttsSpeakId = "completed-speech"
      OmaPilot.OmaPilotStore.ttsSpeaking = true
      OmaPilot.OmaPilotStore.applyEvent({ type: "tts_spoken", id: "completed-speech" })
      if (!ambient.answerSpoken)
        root.fail("completed speech did not select the spoken-answer dismissal")
      if (ambient.dismissDelay !== 2000)
        root.fail("completed speech did not select the two-second dismissal")
      ambient.answerSpoken = false

      ambient.resetFreshVoiceChat()

      if (!ambient.voiceEngaged)
        root.fail("fresh reset dismissed the ambient presentation")
      if (!ambient.voiceSessionActive)
        root.fail("fresh reset closed the voice-session lease")
      if (OmaPilot.OmaPilotStore.state !== "composing")
        root.fail("fresh reset did not return the store to composing")
      if (OmaPilot.OmaPilotStore.currentChatId !== "")
        root.fail("fresh reset retained the completed chat continuation")

      if (!root.failed) console.log("OMAPILOT_AMBIENT_SESSION_LIFECYCLE_PROBE_OK")
      Qt.quit()
    }
  }
}
