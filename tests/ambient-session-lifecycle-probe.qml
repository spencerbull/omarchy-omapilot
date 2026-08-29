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

      OmaPilot.OmaPilotStore.contextAttachments = [{
        id: "captured-image",
        representations: [{ id: "image" }],
        selectedRepresentationIds: ["image"]
      }]
      ambient.preserveCapturedContextOnFreshReset = true
      ambient.resetFreshVoiceChat()

      if (!ambient.voiceEngaged)
        root.fail("fresh reset dismissed the ambient presentation")
      if (!ambient.voiceSessionActive)
        root.fail("fresh reset closed the voice-session lease")
      if (OmaPilot.OmaPilotStore.state !== "composing")
        root.fail("fresh reset did not return the store to composing")
      if (OmaPilot.OmaPilotStore.currentChatId !== "")
        root.fail("fresh reset retained the completed chat continuation")
      if (OmaPilot.OmaPilotStore.contextAttachments.length !== 1)
        root.fail("capture-to-voice fresh reset discarded the selected screenshot")

      if (!root.failed) console.log("OMAPILOT_AMBIENT_SESSION_LIFECYCLE_PROBE_OK")
      Qt.quit()
    }
  }
}
