import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "components" as OmaPilot
import "components/SessionLifecycle.js" as SessionLifecycle

// OmaPilot's ambient overlay root.
//
// This is the plugin's `overlay` entry point, and because the manifest sets
// `keepLoaded`, Omarchy keeps it live from shell start. It owns every desktop
// surface: the voice node, the answer curtain, and the pre-existing explicit
// context-capture overlay.
//
// It is the orchestrator, not a view. The node and the curtain are presentational
// and receive a derived phase; all state derivation, dictation handoff, and
// dismissal policy live here.
Item {
  id: root

  // Injected by the host's panel/overlay loader.
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""
  property var pluginRegistry: null
  property var barWidgetRegistry: null

  readonly property string pluginId: (manifest && manifest.id)
    || "io.github.spencerbull.omapilot"

  // Quattro and Qt 6.11 expose no system reduced-motion preference. Keep motion
  // injectable so a future host signal or setting can switch it off.
  property bool motionEnabled: true

  // ------------------------------------------------------------ placement
  // The output Hyprland has focused — where the user actually is. Every surface
  // follows it, so the light lands on the screen being worked on. Hyprland
  // reports nothing briefly at startup, so fall back rather than render nowhere;
  // this mirrors the caveat the first-party bar documents.
  readonly property string focusedScreenName:
    Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
  readonly property var activeScreen: {
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name || "") === root.focusedScreenName) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  // ------------------------------------------------------------- settings
  // The overlay loader injects `shell`, `manifest`, `pluginRegistry`, and
  // `barWidgetRegistry`, but *not* `settings` — that is a bar-widget-only
  // injection. An overlay-only plugin is enabled by an entry in `shell.json`
  // `plugins[]`, so read our own entry from there and keep writing through
  // `shell.updateEntryInline`, which already has a `plugins[]` branch.
  // Null, not {}, when there is no `plugins[]` entry. That distinction matters
  // during the staged migration: while the bar widget still exists the plugin is
  // enabled through `bar.layout`, the bar widget owns settings injection, and
  // configuring the store from an empty object here would reset the user's
  // provider and model to defaults on every shell load.
  readonly property var ownSettings: {
    var config = root.shell ? root.shell.shellConfig : null
    if (!config || !Array.isArray(config.plugins)) return null
    for (var i = 0; i < config.plugins.length; i++) {
      var entry = config.plugins[i]
      if (entry && String(entry.id || "") === root.pluginId) return entry
    }
    return null
  }

  function persistSettings(values) {
    var entry = { id: root.pluginId }
    for (var existing in root.ownSettings)
      if (existing !== "id") entry[existing] = root.ownSettings[existing]
    for (var key in values) entry[key] = values[key]
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(root.pluginId, entry)
  }

  // Only claim settings authority once we actually own an entry, so the bar
  // widget stays authoritative until it is removed.
  function applyOwnSettings() {
    if (!root.ownSettings) return
    OmaPilot.OmaPilotStore.configure(root.ownSettings)
  }

  onOwnSettingsChanged: applyOwnSettings()
  Component.onCompleted: {
    applyOwnSettings()
    storeState = OmaPilot.OmaPilotStore.state
  }

  // ---------------------------------------------------------------- phase
  // Keep an imperative mirror instead of a binding to the singleton's `state`.
  // The overlay's own derived phase feeds surfaces that participate in shell
  // loading, which made a direct cross-singleton binding loop during updates.
  property string storeState: ""
  readonly property bool hasAnswer: OmaPilot.OmaPilotStore.answerMarkdown !== ""
    || OmaPilot.OmaPilotStore.images.length > 0
  readonly property bool failed: storeState === "error" || storeState === "unavailable"

  Connections {
    target: OmaPilot.OmaPilotStore
    function onStateChanged() { root.storeState = OmaPilot.OmaPilotStore.state }
    function onTtsSpoken() {
      if (!root.voiceEngaged || root.storeState !== "complete") return
      root.answerSpoken = true
    }
    function onIpcVoiceStartRequested() { root.voiceStart() }
    function onIpcVoiceStopRequested() { root.voiceStop() }
    function onIpcVoiceToggleRequested() { root.voiceToggle() }
    function onIpcNewVoiceChatRequested() { root.newVoiceChat() }
    function onIpcVoiceCancelRequested() { root.voiceCancel() }
    function onIpcAmbientDismissRequested() { root.dismiss() }
  }

  // Presentation and conversation lifetime are deliberately separate. A failed
  // launch still engages the node long enough to explain itself, but it has not
  // opened a voice conversation. Once a launch succeeds, that conversation stays
  // active until the ambient flow is dismissed; the next closed-to-open gesture
  // then starts fresh instead of reviving an invisible prior chat.
  property bool voiceEngaged: false
  property bool voiceSessionActive: false

  readonly property bool curtainShown:
    voiceEngaged && (failed || hasAnswer)

  readonly property string phase: {
    if (!voiceEngaged) return "dormant"
    if (voiceNotice !== "") return "error"
    if (failed) return "error"
    if (storeState === "dictating") return "listening"
    if (storeState === "preparing" || storeState === "streaming") return "thinking"
    if (storeState === "complete") return "answering"
    return "dormant"
  }

  // The caption shows the live transcript while listening, and nothing after —
  // once the curtain carries the question, repeating it below is noise.
  readonly property string captionText: voiceNotice !== "" ? voiceNotice
    : (phase === "listening" ? OmaPilot.OmaPilotStore.transcript : "")

  // Shown under the caption while listening. Without it the only way to learn
  // how to finish is to be told, and the surface deliberately has no controls.
  readonly property string captionHint:
    phase === "listening" ? "Super+A to send \u00b7 Super+Alt+X to cancel" : ""

  // ---------------------------------------------------------- voice control
  // Set while a talk gesture is waiting for a preempted turn to unwind.
  property bool voiceStartPending: false
  // Whether that pending gesture must drop the saved continuation before it
  // starts recording. A fresh-chat hotkey can arrive while a turn or dictation
  // is still unwinding, so the reset has to wait for the broker to settle.
  property bool freshVoiceStartPending: false
  // OmaPilotStore.newChat() synchronously publishes its composing state. Keep
  // that intentional reset distinct from an empty completed dictation, which
  // the normal state handler dismisses as a silence-only voice turn.
  property bool freshChatResetInProgress: false
  // Why the node is lit in its error state, shown as the caption.
  property string voiceNotice: ""
  // True after this voice turn's answer has been spoken, so the curtain can
  // linger briefly instead of waiting out a reading-time guess.
  property bool answerSpoken: false

  function resetFreshVoiceChat() {
    freshChatResetInProgress = true
    OmaPilot.OmaPilotStore.newChat()
    freshChatResetInProgress = false
  }

  function beginVoiceChat(freshChat) {
    // A voice hotkey must always produce visible feedback. The first version
    // bailed out whenever the store was busy and still answered "ok" to IPC, so
    // a gesture during an in-flight turn looked indistinguishable from a broken
    // binding.
    var freshChatReset = false

    if (!freshChat && OmaPilot.OmaPilotStore.state === "dictating")
      return "already listening"

    OmaPilot.OmaPilotStore.stopSpeaking()
    voiceNotice = ""
    answerSpoken = false
    voiceEngaged = true

    if (!OmaPilot.OmaPilotStore.voiceEnabled) {
      voiceNotice = "Enable voice in OmaPilot Settings"
      return "disabled"
    }

    if (!OmaPilot.OmaPilotStore.initialized) {
      // Light the node instead of failing invisibly, so a hotkey press always
      // produces something on screen.
      voiceNotice = OmaPilot.OmaPilotStore.statusMessage !== ""
        ? OmaPilot.OmaPilotStore.statusMessage
        : "OmaPilot is not ready yet"
      return "not ready"
    }

    // A fresh chat deliberately clears a saved conversation's continuation
    // block, but it still needs the currently selected harness to be ready.
    if (!OmaPilot.OmaPilotStore.providerReady
        || (!freshChat && OmaPilot.OmaPilotStore.continuationBlocked)) {
      voiceNotice = OmaPilot.OmaPilotStore.statusMessage !== ""
        ? OmaPilot.OmaPilotStore.statusMessage
        : "Choose an available harness in OmaPilot Settings"
      return "not ready"
    }

    if (!freshChat && OmaPilot.OmaPilotStore.pendingHerdrChatId !== "") {
      voiceNotice = "Continue in Herdr is still opening"
      return "busy"
    }

    voiceSessionActive = true

    // A fresh voice gesture supersedes presentation of an in-flight Herdr
    // handoff. The external handoff may still finish, but its tagged outcome is
    // ignored once newChat clears pendingHerdrChatId.
    if (freshChat && OmaPilot.OmaPilotStore.pendingHerdrChatId !== "") {
      resetFreshVoiceChat()
      freshChatReset = true
    }

    OmaPilot.OmaPilotStore.latchDesktopContext()

    if (OmaPilot.OmaPilotStore.busy) {
      // Dictation cannot start while the broker is mid-response, and the broker
      // clears busy asynchronously, so arm the start and let the state change
      // below run it once the previous turn has unwound.
      voiceStartPending = true
      // Once any gesture has requested a fresh session, later taps during the
      // same cancellation window must not downgrade it back to continuation.
      freshVoiceStartPending = freshVoiceStartPending || freshChat
      OmaPilot.OmaPilotStore.cancel()
      return "preempting"
    }

    if (freshChat && !freshChatReset) resetFreshVoiceChat()

    if (!OmaPilot.OmaPilotStore.startDictation()) {
      voiceNotice = OmaPilot.OmaPilotStore.statusMessage !== ""
        ? OmaPilot.OmaPilotStore.statusMessage : "Voice input is not available right now"
      return "not ready"
    }
    return "listening"
  }

  function voiceStart() { return beginVoiceChat(!voiceSessionActive) }

  function newVoiceChat() { return beginVoiceChat(true) }

  function voiceStop() {
    if (OmaPilot.OmaPilotStore.state !== "dictating") return
    OmaPilot.OmaPilotStore.stopDictation()
  }

  // Toggle is the default gesture because nothing can detect end-of-speech for
  // us: Voxtype's VAD only discards silence-only recordings before
  // transcription, it never ends a recording. So the user has to say when they
  // are done, and holding a key through a whole sentence is worse than tapping
  // twice. `voiceStart`/`voiceStop` remain separately bindable for anyone who
  // prefers true push-to-talk.
  function voiceToggle() {
    var activation = SessionLifecycle.voiceActivationMode(
      voiceSessionActive, OmaPilot.OmaPilotStore.state)
    if (activation === "finish") {
      OmaPilot.OmaPilotStore.stopDictation()
      return "finishing"
    }
    return beginVoiceChat(activation === "fresh")
  }

  function voiceCancel() {
    OmaPilot.OmaPilotStore.cancel()
    dismiss()
  }

  function dismiss() {
    voiceStartPending = false
    freshVoiceStartPending = false
    voiceNotice = ""
    answerSpoken = false
    OmaPilot.OmaPilotStore.stopSpeaking()
    // Releasing the surfaces must also release the microphone. Dismissing while
    // dictation is still live would leave a hot mic with no indicator on screen,
    // which is the one failure mode an invisible ambient layer must never have.
    if (OmaPilot.OmaPilotStore.state === "dictating")
      OmaPilot.OmaPilotStore.cancel()
    voiceSessionActive = false
    voiceEngaged = false
    OmaPilot.OmaPilotStore.clearDesktopContextLatch()
  }

  // Dictation ends in "composing" with the transcript populated. In the voice
  // flow that is the submit signal: the user already spoke their intent, so
  // making them confirm it in a text box would defeat the gesture.
  onStoreStateChanged: {
    if (freshChatResetInProgress) return
    if (voiceStartPending && !OmaPilot.OmaPilotStore.busy) {
      var freshChat = freshVoiceStartPending
      voiceStartPending = false
      freshVoiceStartPending = false
      // Finish applying the cancellation event before resetting presentation
      // state or sending the next command. Otherwise the old event can overwrite
      // the fresh chat's status after this handler returns.
      Qt.callLater(function() {
        if (!root.voiceEngaged) return
        if (freshChat) root.resetFreshVoiceChat()
        if (!OmaPilot.OmaPilotStore.startDictation()) {
          root.voiceNotice = OmaPilot.OmaPilotStore.statusMessage !== ""
            ? OmaPilot.OmaPilotStore.statusMessage : "Voice input is not available right now"
        }
      })
      return
    }
    if (!voiceEngaged) return
    if (storeState === "complete") {
      var answer = String(OmaPilot.OmaPilotStore.answerMarkdown || "").trim()
      if (answer !== "") OmaPilot.OmaPilotStore.speakAnswer(answer)
      return
    }
    if (storeState !== "composing") return
    var spoken = String(OmaPilot.OmaPilotStore.transcript || "").trim()
    if (spoken === "") { dismiss(); return }
    if (!OmaPilot.OmaPilotStore.submit(spoken)) {
      voiceNotice = OmaPilot.OmaPilotStore.statusMessage !== ""
        ? OmaPilot.OmaPilotStore.statusMessage : "The selected harness cannot accept this request"
    }
  }

  // ------------------------------------------------------------- dismissal
  // Scaled to how much there is to read rather than a flat timeout, because a
  // fixed delay eats a long answer mid-sentence. Roughly 240ms per word over a
  // floor, clamped so a one-liner still lingers and an essay cannot camp on the
  // desktop.
  readonly property int dismissDelay: {
    if (root.answerSpoken) return 2000
    var words = String(OmaPilot.OmaPilotStore.answerMarkdown || "")
      .split(/\s+/).filter(function(w) { return w !== "" }).length
    return Math.max(6000, Math.min(40000, 4500 + words * 240))
  }

  // A "not ready" notice is transient feedback, not a failure to act on, so it
  // clears itself rather than leaving the node lit indefinitely.
  Timer {
    id: noticeTimer
    interval: 4000
    repeat: false
    running: root.voiceNotice !== ""
    onTriggered: root.dismiss()
  }

  Timer {
    id: dismissTimer
    interval: root.dismissDelay
    repeat: false
    // Only armed once the answer has settled, so streaming never races it.
    // Errors stay until dismissed: a failure the user missed is worse than a
    // surface that lingers.
    running: root.phase === "answering" && !OmaPilot.OmaPilotStore.ttsSpeaking
    onTriggered: root.dismiss()
  }

  // --------------------------------------------------------------- IPC routing
  // The voice gesture cannot be a surface keybinding, because the ambient
  // surfaces never take keyboard focus by design. It has to arrive over IPC from
  // a compositor binding. OmaPilotStore owns the plugin's one IPC target and
  // relays voice requests here; registering a second handler would make
  // Quickshell reject one entire action set. The default gesture derives
  // fresh-versus-continue from the ambient session lease; `newVoiceChat`
  // remains an explicit force-new escape hatch while that lease is still active.

  // --------------------------------------------------------------- surfaces
  OmaPilot.VoiceNode {
    phase: root.phase
    transcript: root.captionText
    status: OmaPilot.OmaPilotStore.statusMessage
    speaking: OmaPilot.OmaPilotStore.ttsPlaybackActive
    playbackMetered: OmaPilot.OmaPilotStore.ttsPlaybackMetered
    playbackLevel: OmaPilot.OmaPilotStore.ttsLevel
    listeningMetered: OmaPilot.OmaPilotStore.dictationMetered
    listeningLevel: OmaPilot.OmaPilotStore.dictationLevel
    voiceVisualizer: OmaPilot.OmaPilotStore.voiceVisualizer
    hint: root.captionHint
    targetScreen: root.activeScreen
    motionEnabled: root.motionEnabled
  }

  OmaPilot.AnswerCurtain {
    shown: root.curtainShown
    question: OmaPilot.OmaPilotStore.question
    markdown: OmaPilot.OmaPilotStore.answerMarkdown
    images: OmaPilot.OmaPilotStore.images
    failed: root.failed
    provenance: root.failed
      ? String(OmaPilot.OmaPilotStore.statusMessage || "could not answer")
      : (OmaPilot.OmaPilotStore.provider
         + (OmaPilot.OmaPilotStore.model !== "" ? " · " + OmaPilot.OmaPilotStore.model : ""))
    targetScreen: root.activeScreen
    motionEnabled: root.motionEnabled
    onLinkActivated: function(url) { OmaPilot.OmaPilotStore.activateLink(url) }
  }

  // The explicit context-capture overlay is unchanged and still owns the
  // host's summon payload contract.
  ContextCaptureOverlay {
    id: capture
    shell: root.shell
    manifest: root.manifest
  }

  // Host contract: `shell.summon(id, payload)` calls open() and `shell.hide(id)`
  // calls close(). Context capture is the only flow that carries a payload, so
  // route a payload-bearing summon to it and treat a bare summon as a dismissal
  // of the ambient surfaces.
  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(String(payloadJson || "{}")) || {} } catch (error) { payload = {} }
    if (payload && payload.id) {
      capture.open(payloadJson)
      return
    }
    dismiss()
  }

  function close() {
    capture.close()
    dismiss()
  }

  readonly property bool opened: capture.opened === true || root.voiceEngaged
}
