#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
omarchy_shell="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
smoke_root=""
preview_root=""

cleanup() {
  if [[ -n $smoke_root && -d $smoke_root ]]; then rm -rf -- "$smoke_root"; fi
  if [[ -n $preview_root && -d $preview_root ]]; then rm -rf -- "$preview_root"; fi
}
trap cleanup EXIT

qml_files=(
  "$repo_dir/BarWidget.qml"
  "$repo_dir/ContextCaptureOverlay.qml"
  "$repo_dir/Panel.qml"
  "$repo_dir/components/Composer.qml"
  "$repo_dir/components/BumperVisualizer.qml"
  "$repo_dir/components/CommandReceipt.qml"
  "$repo_dir/components/ContextAttachmentPreview.qml"
  "$repo_dir/components/ErrorDetailsView.qml"
  "$repo_dir/components/ErrorNotice.qml"
  "$repo_dir/components/HistoryView.qml"
  "$repo_dir/components/ListeningVisualizer.qml"
  "$repo_dir/components/MarkdownView.qml"
  "$repo_dir/components/OmaPilotHeader.qml"
  "$repo_dir/components/OmaPilotMark.qml"
  "$repo_dir/components/QuickActions.qml"
  "$repo_dir/components/QuickActionEditor.qml"
  "$repo_dir/components/SettingsView.qml"
  "$repo_dir/components/SettingsTabs.qml"
  "$repo_dir/components/SegmentVisualizer.qml"
  "$repo_dir/components/SetupGuide.qml"
  "$repo_dir/components/SpectrumVisualizer.qml"
  "$repo_dir/components/StateLightBar.qml"
  "$repo_dir/components/ThinkingScanner.qml"
  "$repo_dir/components/VoiceNode.qml"
  "$repo_dir/components/VoiceWave.qml"
  "$repo_dir/components/DotFieldVisualizer.qml"
  "$repo_dir/components/ActivityFilament.qml"
  "$repo_dir/components/AnswerCurtain.qml"
  "$repo_dir/components/ResponseActivityBorder.qml"
  "$repo_dir/components/ResponseAction.qml"
  "$repo_dir/components/ResponseBadge.qml"
  "$repo_dir/components/internal/PermissionFocusGuard.qml"
  "$repo_dir/components/internal/PanelKeyboardNavigation.qml"
  "$repo_dir/components/internal/HistoryListKeyboardHandler.qml"
  "$repo_dir/components/OmaPilotStore.qml"
  "$repo_dir/components/DesktopContext.qml"
  "$repo_dir/components/Protocol.js"
  "$repo_dir/components/Presentation.js"
  "$repo_dir/components/QuickActions.js"
  "$repo_dir/tests/answer-curtain-preview.qml"
  "$repo_dir/tests/motion-preview.qml"
  "$repo_dir/tests/state-motion-preview.qml"
  "$repo_dir/tests/listening-visualizers-preview.qml"
  "$repo_dir/tests/voice-node-preview.qml"
)

/usr/lib/qt6/bin/qmllint -I "$omarchy_shell" -I "$repo_dir" "${qml_files[@]}" >/dev/null 2>&1

grep -Fq 'Qt.resolvedUrl("../runtime/bin/omapilot-broker")' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'Quickshell.env("OMAPILOT_BROKER_PATH") || bundledBrokerPath' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'Qt.resolvedUrl("../scripts/install-hotkeys.sh")' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'command: [root.hotkeyInstallerPath, "--installed-plugin-only"]' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'running: false' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'function installHotkeys()' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'onHotkeyInstallRequested: OmaPilot.OmaPilotStore.installHotkeys()' \
  "$repo_dir/Panel.qml"
grep -Fq 'text: root.hotkeyBusy ? "Updating hotkeys…" : "Install global hotkeys"' \
  "$repo_dir/components/SettingsView.qml"
grep -Fq 'OmaPilot.SetupGuide {' "$repo_dir/Panel.qml"
grep -Fq 'function setupStage(providerReady, voiceEnabled, ttsReady, onboardingComplete)' \
  "$repo_dir/components/Presentation.js"
grep -Fq 'onActionRequested: root.openSettings(root.setupStage === "voice" ? "voice" : "desktop")' \
  "$repo_dir/Panel.qml"
grep -Fq 'function onHotkeyInstalled()' "$repo_dir/Panel.qml"
grep -Fq 'if (root.voiceSetupReady) root.persistSettings({ onboardingComplete: true })' \
  "$repo_dir/Panel.qml"
grep -Fq 'signal hotkeyInstalled()' "$repo_dir/components/OmaPilotStore.qml"
if grep -Fq 'command: [root.hotkeyInstallerPath, "--once"' \
  "$repo_dir/components/OmaPilotStore.qml"; then
  printf 'Hotkey installation must require an explicit settings action\n' >&2
  exit 1
fi
grep -Fq -- '-- BEGIN OmaPilot managed hotkeys' \
  "$repo_dir/scripts/install-hotkeys.sh"
grep -Fq 'property string configuredProvider: "builtin"' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'harness: provider' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'readonly property var modeProviders: Protocol.harnessOptions()' \
  "$repo_dir/components/SettingsView.qml"
grep -Fq 'text: "Open sign-in page"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'sendCommand(Protocol.command("auth_begin", { methodId: selected }))' \
  "$repo_dir/components/OmaPilotStore.qml"
if grep -Fq 'PI_CODING_AGENT_DIR' "$repo_dir/components/OmaPilotStore.qml"; then
  printf 'Built-in authentication must stay embedded instead of launching Pi\n' >&2
  exit 1
fi
if grep -Fq 'backendSelection' "$repo_dir/components/OmaPilotStore.qml"; then
  printf 'Harness selection must not be split into backend and provider settings\n' >&2
  exit 1
fi
grep -Fq 'property bool desktopContextEnabled: true' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'property string webHandoffProvider: "duckduckgo"' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'webHandoffProvider))' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'DesktopContext.snapshot()' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'Protocol.hasFeature(event.features, "desktop-context")' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'import Quickshell.Hyprland' "$repo_dir/components/DesktopContext.qml"
grep -Fq 'import Quickshell.Services.Mpris' "$repo_dir/components/DesktopContext.qml"
awk '
  /^[[:space:]]*function / { latched = 0 }
  /OmaPilot\.OmaPilotStore\.latchDesktopContext\(\)/ { latched = 1 }
  /root\.controller\.show\(\)/ { if (!latched) exit 1; shows += 1 }
  END { if (shows < 3) exit 1 }
' "$repo_dir/Panel.qml"
awk '
  /^[[:space:]]*function / { cleared = 0 }
  /OmaPilot\.OmaPilotStore\.clearDesktopContextLatch\(\)/ { cleared = 1 }
  /root\.controller\.hide\(\)/ { if (!cleared) exit 1; hides += 1 }
  END { if (hides < 2) exit 1 }
' "$repo_dir/Panel.qml"
awk '
  /function desktopContextForSubmit\(\)/ { inside = 1; gated = 0 }
  inside && /if \(!desktopContextActive\) return null/ { gated = 1 }
  inside && /DesktopContext\.snapshot\(\)/ { if (!gated) exit 1; found = 1; exit }
  END { if (!found) exit 1 }
' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'if (context && context.activeWindow) latchedActiveWindow = context.activeWindow' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'if (!changed) return' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'model = desiredModel' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'if (providers.length > 0) selectProvider(provider)' \
  "$repo_dir/components/OmaPilotStore.qml"
test "$(grep -Fc 'root.pendingPermission = null' "$repo_dir/components/OmaPilotStore.qml")" -ge 2
test "$(grep -Fc 'root.permissionQueue = []' "$repo_dir/components/OmaPilotStore.qml")" -ge 2
grep -Fq 'signal escapeRequested()' "$repo_dir/components/Composer.qml"
grep -Fq 'Protocol.providerPolicyDescription(root.backend.provider, root.backend.providerPolicy)' "$repo_dir/components/SettingsView.qml"
grep -Fq 'policy.web === "search"' "$repo_dir/components/Protocol.js"
grep -Fq 'policy.web === "approved-command"' "$repo_dir/components/Protocol.js"
if grep -Fq 'ButtonGroup {' "$repo_dir/components/Composer.qml"; then
  printf 'Composer must not expose a capability mode selector\n' >&2
  exit 1
fi
grep -Fq 'Protocol.hasFeature(event.features, "capability-packs")' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'sendCommand(Protocol.command("capability_set_enabled"' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'sendCommand(Protocol.command("capability_files_root_set"' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'visible: root.selectedTab === "skills"' \
  "$repo_dir/components/SettingsView.qml"
if grep -Eqi 'if .*local_action|local_action.*sendCommand' \
    "$repo_dir/Panel.qml" "$repo_dir/components/OmaPilotStore.qml"; then
  printf 'QML must not hardcode local-action execution routing\n' >&2
  exit 1
fi
grep -Fq 'visible: !root.backend || root.backend.pendingPermission === null' \
  "$repo_dir/components/Composer.qml"
if grep -Eq 'sandboxed|Device commands stay blocked|sandbox limits stay active' \
  "$repo_dir/Panel.qml" "$repo_dir/components/Protocol.js"; then
  printf 'QML permission copy must not retain unreachable legacy policy branches\n' >&2
  exit 1
fi
grep -Fq 'Review the exact request before it runs.' \
  "$repo_dir/Panel.qml"
grep -Fq 'readonly property bool popupOpen:' "$repo_dir/components/Composer.qml"
grep -Fq 'var action = Presentation.escapeAction(root.viewMode, composer.popupOpen,' "$repo_dir/Panel.qml"
grep -Fq 'if (action === "close-composer-popup") composer.closePopups()' "$repo_dir/Panel.qml"
grep -Fq 'OmaPilot.SettingsView {' "$repo_dir/Panel.qml"
grep -Fq 'visible: root.viewMode === "settings"' "$repo_dir/Panel.qml"
grep -Fq 'settingsView.popupOpen' "$repo_dir/Panel.qml"
# The panel keeps a single frame: the composer, one answer seam, a response class
# badge/receipt, and a compact keyboard footer.
if grep -Fq 'OmaPilot.OmaPilotHeader {' "$repo_dir/Panel.qml"; then
  printf 'Panel must not reintroduce the OmaPilot header chrome\n' >&2
  exit 1
fi
if grep -Fq 'ActivityFilament {' "$repo_dir/components/Composer.qml"; then
  printf 'The composer must not draw a second rule above the answer seam\n' >&2
  exit 1
fi
grep -Fq 'id: answerCard' "$repo_dir/Panel.qml"
grep -Fq 'Layout.minimumHeight: 0' \
  "$repo_dir/Panel.qml"
grep -Fq 'visible: answerCard.contentVisible' "$repo_dir/Panel.qml"
grep -Fq 'readonly property bool atmosphereActive: motionEnabled' \
  "$repo_dir/components/StateLightBar.qml"
grep -Fq '&& (phase === "listening" || phase === "thinking")' \
  "$repo_dir/components/StateLightBar.qml"
grep -Fq 'running: root.atmosphereActive' "$repo_dir/components/StateLightBar.qml"
grep -Fq 'StateColor.forPhase' "$repo_dir/components/StateLightBar.qml"
grep -Fq 'colorizationColor: root.displayedColor' "$repo_dir/components/StateLightBar.qml"
grep -Fq 'readonly property real glowCenter: thinking' "$repo_dir/components/StateLightBar.qml"
grep -Fq 'root.travel = (root.travel + 0.0095) % 1' "$repo_dir/components/StateLightBar.qml"
grep -Fq 'id: promptRow' "$repo_dir/components/Composer.qml"
grep -Fq 'iconText: "󰹑"' "$repo_dir/components/Composer.qml"
grep -Fq '󰍬' "$repo_dir/components/Composer.qml"
if grep -Fq 'Active window, open apps, workspaces, and playing media' \
    "$repo_dir/components/Composer.qml"; then
  printf 'Desktop context disclosure must be the hostname, not a capability list\n' >&2
  exit 1
fi
grep -Fq 'font.pixelSize: 17' "$repo_dir/components/Composer.qml"
grep -Fq 'cursorDelegate: Rectangle {' "$repo_dir/components/Composer.qml"
grep -Fq 'sequences: ["Ctrl+H"]' "$repo_dir/Panel.qml"
grep -Fq 'OmaPilot.ResponseBadge {' "$repo_dir/Panel.qml"
grep -Fq 'OmaPilot.CommandReceipt {' "$repo_dir/Panel.qml"
grep -Fq 'ResponseAction 1.0 ResponseAction.qml' "$repo_dir/components/qmldir"
grep -Fq 'id: responseHeader' "$repo_dir/Panel.qml"
grep -Fq 'id: copyAnswerAction' "$repo_dir/Panel.qml"
grep -Fq 'id: sessionActions' "$repo_dir/Panel.qml"
grep -Fq 'text: "COPY"' "$repo_dir/Panel.qml"
grep -Fq 'text: "NEW CHAT"' "$repo_dir/Panel.qml"
grep -Fq 'text: "CONTINUE IN HERDR"' "$repo_dir/Panel.qml"
grep -Fq 'Presentation.footerKeyHints' "$repo_dir/Panel.qml"
if grep -Fq 'Ctrl+,' "$repo_dir/Panel.qml" "$repo_dir/components/Composer.qml"; then
  printf 'Settings must use only the desktop-global Super+Alt+P binding\n' >&2
  exit 1
fi
if grep -Fq 'id: caret' "$repo_dir/components/Composer.qml"; then
  printf 'Prompt text must share the content left edge without a decorative caret\n' >&2
  exit 1
fi
grep -Fq 'dangerousAutoApprove: root.dangerousAutoApprove' "$repo_dir/Panel.qml"
grep -Fq 'text: "OmaPilot"' "$repo_dir/components/OmaPilotHeader.qml"
grep -Fq 'source: Qt.resolvedUrl("../assets/omapilot-mark.png")' \
  "$repo_dir/components/OmaPilotMark.qml"
grep -Fq 'display: QQC.AbstractButton.IconOnly' "$repo_dir/components/OmaPilotMark.qml"
grep -Fq 'icon.color: root.accent' "$repo_dir/components/OmaPilotMark.qml"
grep -Fq 'iconComponent: Component {' "$repo_dir/BarWidget.qml"
test -s "$repo_dir/assets/omapilot-mark.png"
if grep -RFq 'interactionMode' "$repo_dir/BarWidget.qml" "$repo_dir/Panel.qml" "$repo_dir/components"; then
  printf 'OmaPilot must not retain Ask/Act presentation state\n' >&2
  exit 1
fi
if [[ -e "$repo_dir/components/ModeSwitch.qml" ]]; then
  printf 'OmaPilot must not retain the Ask/Act mode switch\n' >&2
  exit 1
fi
grep -Fq 'visible: OmaPilot.OmaPilotStore.pendingPermission !== null' "$repo_dir/Panel.qml"
grep -Fq 'OmaPilot.QuickActions {' "$repo_dir/Panel.qml"
grep -Fq 'workInAppShortcutText: "Ctrl+Shift+A"' "$repo_dir/Panel.qml"
grep -Fq 'sequence: "Ctrl+Shift+A"' \
  "$repo_dir/components/internal/PanelKeyboardNavigation.qml"
if grep -RFq 'Ctrl+Alt+A' "$repo_dir/Panel.qml" "$repo_dir/components"; then
  printf 'OmaPilot production QML must not retain the AltGr-aliased shortcut\n' >&2
  exit 1
fi
grep -Fq 'var prompt = ActionCatalog.promptFor(root.quickActionItems, "work-in-app")' \
  "$repo_dir/Panel.qml"
grep -Fq 'composer.setDraft(prompt)' "$repo_dir/Panel.qml"
test "$(grep -Fc '&& !OmaPilot.OmaPilotStore.busy' "$repo_dir/Panel.qml")" -ge 2
grep -Fq 'modalInteractionActive: root.modalInteractionActive' \
  "$repo_dir/Panel.qml"
grep -Fq 'Accessible.name: tooltipText' "$repo_dir/components/QuickActions.qml"
grep -Fq 'quickActionsJson' "$repo_dir/Panel.qml"
grep -Fq 'onQuickActionsEdited:' "$repo_dir/Panel.qml"
grep -Fq 'Accessible.name: "OmaPilot settings"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'SettingsTabs {' "$repo_dir/components/SettingsView.qml"
grep -Fq 'property string selectedTab: "agent"' "$repo_dir/components/SettingsView.qml"
grep -Fq '{ id: "agent", label: "Agent" }' "$repo_dir/components/Presentation.js"
grep -Fq 'QuickActionEditor {' "$repo_dir/components/SettingsView.qml"
grep -Fq 'maximumActions = 5' "$repo_dir/components/QuickActions.js"
grep -Fq 'function moveAction(actions, index, delta)' "$repo_dir/components/QuickActions.js"
grep -Fq 'function removeAction(actions, index)' "$repo_dir/components/QuickActions.js"
grep -Fq 'ActionCatalog.addAction(' "$repo_dir/components/QuickActionEditor.qml"
grep -Fq 'ActionCatalog.updateAction(' "$repo_dir/components/QuickActionEditor.qml"
grep -Fq 'label: "Dangerous auto-approve"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'label: "Desktop context"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'text: "Search provider"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'Accessible.name: "Search provider"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'onWebHandoffProviderRequested:' "$repo_dir/Panel.qml"
grep -Fq '"webHandoffProvider": "duckduckgo"' "$repo_dir/manifest.json"
grep -Fq '{ id: "voice", label: "Voice" }' "$repo_dir/components/Presentation.js"
grep -Fq 'visible: root.selectedTab === "voice"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'label: "Enable voice"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'text: "Listening"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'text: "Speaking"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'Accessible.name: "TTS provider"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'Accessible.name: "TTS model"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'Accessible.name: "TTS voice"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'function requestVoiceStatus()' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'Protocol.command("voice_status")' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'Protocol.ttsKeySetCommand(provider, apiKey)' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'onVoiceEnabledRequested:' "$repo_dir/Panel.qml"
grep -Fq 'if (!OmaPilot.OmaPilotStore.voiceEnabled)' "$repo_dir/Ambient.qml"
grep -Fq 'function newVoiceChat() {' "$repo_dir/Ambient.qml"
grep -Fq 'function onIpcNewVoiceChatRequested() { root.newVoiceChat() }' \
  "$repo_dir/Ambient.qml"
grep -Fq 'property bool voiceSessionActive: false' "$repo_dir/Ambient.qml"
grep -Fq 'SessionLifecycle.voiceActivationMode(' "$repo_dir/Ambient.qml"
grep -Fq 'voiceSessionActive = false' "$repo_dir/Ambient.qml"
grep -Fq 'function status(): string { return "store=" + root.state }' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'freshVoiceStartPending = freshVoiceStartPending || freshChat' \
  "$repo_dir/Ambient.qml"
grep -Fq 'property bool freshChatResetInProgress: false' "$repo_dir/Ambient.qml"
grep -Fq 'if (freshChatResetInProgress) return' "$repo_dir/Ambient.qml"
grep -Fq 'if (freshChat && !freshChatReset) resetFreshVoiceChat()' \
  "$repo_dir/Ambient.qml"
grep -Fq 'function continueInHerdr() { root.continueInHerdr() }' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq '|| (pendingHerdrChatId === "" && currentId !== "" && busy)' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'if (root.newChatPending && !root.busy) root.resetChat()' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'submittedResumeChatId = resumeChatId' "$repo_dir/components/OmaPilotStore.qml"
test "$(grep -Fc 'restoreSubmittedContinuation()' \
  "$repo_dir/components/OmaPilotStore.qml")" -ge 3
grep -Fq 'pendingHerdrChatId = currentChatId' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'String(event.chatId || "") !== pendingHerdrChatId' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'SUPER + SHIFT + A' "$repo_dir/README.md"
grep -Fq 'io.github.spencerbull.omapilot newVoiceChat' "$repo_dir/README.md"
grep -Fq 'SUPER + ALT + N' "$repo_dir/README.md"
grep -Fq 'io.github.spencerbull.omapilot continueInHerdr' "$repo_dir/README.md"
if grep -Fq 'text: "Voice indicator"' "$repo_dir/components/SettingsView.qml"; then
  printf 'Voice settings must own listening and speaking, not only the Voxtype OSD\n' >&2
  exit 1
fi
grep -Fq 'voice-auth.json' "$repo_dir/runtime/src/tts.ts"
grep -Fq 'id: "kokoro"' "$repo_dir/runtime/src/tts.ts"
grep -Fq 'elevenlabs: "ElevenLabs"' "$repo_dir/runtime/src/tts.ts"
grep -Fq 'const ELEVENLABS_VOICES_URL = "https://api.elevenlabs.io/v2/voices"' \
  "$repo_dir/runtime/src/tts.ts"
grep -Fq 'url.searchParams.set("page_size", String(ELEVENLABS_VOICE_PAGE_SIZE))' \
  "$repo_dir/runtime/src/tts.ts"
grep -Fq 'wyWA56cQNU2KqUW4eCsI' "$repo_dir/runtime/src/tts.ts"
grep -Fq 'wyWA56cQNU2KqUW4eCsI' "$repo_dir/components/Protocol.js"
grep -Fq 'function ttsSpeakCommand' "$repo_dir/components/Protocol.js"
grep -Fq 'function speakAnswer' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'property bool ttsPlaybackMetered: false' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'if (type === "tts_level")' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'playbackLevel: OmaPilot.OmaPilotStore.ttsLevel' "$repo_dir/Ambient.qml"
grep -Fq 'function normalizedTtsLevel(event)' "$repo_dir/components/Protocol.js"
grep -Fq 'OmaPilot.OmaPilotStore.speakAnswer(answer)' "$repo_dir/Ambient.qml"
grep -Fq 'https://api.elevenlabs.io/v1/text-to-speech/' "$repo_dir/runtime/src/tts.ts"
grep -Fq 'https://api.openai.com/v1/audio/speech' "$repo_dir/runtime/src/tts.ts"
grep -Fq 'export function pcm16Envelope(' "$repo_dir/runtime/src/tts.ts"
grep -Fq 'type: "tts_level"' "$repo_dir/runtime/src/types.ts"
grep -Fq 'type: "dictation_level"' "$repo_dir/runtime/src/types.ts"
grep -Fq 'resolveExecutable("voxtype-audio-bridge"' \
  "$repo_dir/runtime/src/dictation.ts"
grep -Fq 'if (type === "dictation_level")' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'listeningLevel: OmaPilot.OmaPilotStore.dictationLevel' "$repo_dir/Ambient.qml"
grep -Fq 'function normalizedDictationLevel(event)' "$repo_dir/components/Protocol.js"
grep -Fq 'function normalizedVoiceVisualizer(value)' "$repo_dir/components/Protocol.js"
grep -Fq 'function voiceVisualizerOptions()' "$repo_dir/components/Protocol.js"
grep -Fq 'property string voiceVisualizer: "kitt"' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'voiceVisualizer: OmaPilot.OmaPilotStore.voiceVisualizer' "$repo_dir/Ambient.qml"
grep -Fq 'id: voiceVisualizerPicker' "$repo_dir/components/SettingsView.qml"
grep -Fq 'Accessible.name: "Listening visualizer"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'voiceVisualizerPicker.popupOpen' "$repo_dir/components/SettingsView.qml"
grep -Fq 'voiceVisualizerPicker.close()' "$repo_dir/components/SettingsView.qml"
grep -Fq 'onVoiceVisualizerRequested:' "$repo_dir/Panel.qml"
grep -Fq 'https://api.openai.com/v1/models' "$repo_dir/runtime/src/tts.ts"
grep -Fq 'text: "Browser context"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'onDesktopContextRequested:' "$repo_dir/Panel.qml"
grep -Fq 'text: "History"' "$repo_dir/components/HistoryView.qml"
grep -Fq 'ActivityFilament {' "$repo_dir/components/HistoryView.qml"
grep -Fq 'text: root.browserCompanion.relayInstalled === true ? "Repair browser setup" : "Enable browser context"' \
  "$repo_dir/components/SettingsView.qml"
grep -Fq 'onBrowserCompanionInstallRequested:' "$repo_dir/Panel.qml"
grep -Fq 'Protocol.command("browser_companion_install")' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'Protocol.command("browser_companion_uninstall")' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'Protocol.command("browser_companion_open_settings", { family: selected })' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'text: "Open Firefox debugging"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'Accessible.name: "Copy Firefox extension folder path"' \
  "$repo_dir/components/SettingsView.qml"
grep -Fq 'text: root.browserRemoveConfirmation ? "Confirm removal" : "Remove browser context"' \
  "$repo_dir/components/SettingsView.qml"
grep -Fq 'onDangerousAutoApproveRequested:' "$repo_dir/Panel.qml"
awk '
  /function close\(\)/ { inside = 1; cleared = 0 }
  inside && /OmaPilot\.OmaPilotStore\.clearContextAttachments\(\)/ { cleared = 1 }
  inside && /root\.controller\.hide\(\)/ { if (!cleared) exit 1; found = 1; exit }
  END { if (!found) exit 1 }
' "$repo_dir/Panel.qml"
grep -Fq 'backend.submit(draftText)' \
  "$repo_dir/components/Composer.qml"
grep -Fq 'var autoApprove = configuredDangerousAutoApprove' \
  "$repo_dir/components/OmaPilotStore.qml"
if grep -Fq 'tooltipText: "Close OmaPilot"' "$repo_dir/Panel.qml" "$repo_dir/components/SettingsView.qml"; then
  printf 'OmaPilot must rely on panel dismissal rather than a redundant close control\n' >&2
  exit 1
fi
grep -Fq 'Presentation.boundedPanelHeight(root.activeNaturalHeight' "$repo_dir/Panel.qml"
grep -Fq 'popup.availableCardHeight * 0.78' "$repo_dir/Panel.qml"
grep -Fq 'id: responseViewport' "$repo_dir/Panel.qml"
grep -Fq 'property bool followLatest: true' "$repo_dir/Panel.qml"
grep -Fq 'onMovementEnded: followLatest = Presentation.isNearBottom(' "$repo_dir/Panel.qml"
grep -Fq 'tooltipText: "Jump to the newest response"' "$repo_dir/Panel.qml"
# The perimeter runner circled the answer card's border. The redesign removed
# that border, so state now lives in the persistent answer seam. The old
# component remains for its motion probe and preview fixtures, but the panel
# must not put a runner back around the response.
if grep -Fq 'OmaPilot.ResponseActivityBorder {' "$repo_dir/Panel.qml"; then
  printf 'Panel must not reintroduce the response perimeter runner\n' >&2
  exit 1
fi
grep -Fq 'id: sweepSource' "$repo_dir/components/ActivityFilament.qml"
# Every state must resolve through one mapping rather than hardcoding accent.
grep -Fq 'StateColor.forPhase' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'anchors { left: parent.left; right: parent.right }' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'property real tide: 0.35' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'property real drift: 0' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'readonly property bool atmosphereActive: motionEnabled' "$repo_dir/components/VoiceNode.qml"
grep -Fq '&& (phase === "listening" || phase === "thinking" || speaking)' \
  "$repo_dir/components/VoiceNode.qml"
grep -Fq 'readonly property bool voiceWaveActive: listeningVisualizerActive || speakingLineActive' \
  "$repo_dir/components/VoiceNode.qml"
grep -Fq 'readonly property bool thinkingScannerActive: phase === "thinking"' \
  "$repo_dir/components/VoiceNode.qml"
grep -Fq 'id: thinkingScanner' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'active: root.thinkingScannerActive' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'playbackMetered ? Math.max(0, Math.min(1, playbackLevel))' \
  "$repo_dir/components/VoiceNode.qml"
grep -Fq 'listeningMetered ? Math.max(0, Math.min(1, listeningLevel))' \
  "$repo_dir/components/VoiceNode.qml"
grep -Fq 'running: root.atmosphereActive' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'running: root.motionEnabled && root.lit && root.phase !== "listening"' "$repo_dir/components/VoiceNode.qml"
grep -Fq '0.50 + root.organicDrift * 0.075' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'Math.sin(livingPhase * 1.618 + 1.1)' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'id: listeningVisualizer' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'visualizer: root.voiceVisualizer' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'id: speakingWave' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'visualizer: "line"' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'motionStyle: "speaking"' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'readonly property real motionPace: thinking ? 0.084 : (speaking ? 0.033 : 0.022)' \
  "$repo_dir/components/VoiceWave.qml"
grep -Fq 'var travel = (root.phase * 0.095) % 1' "$repo_dir/components/VoiceWave.qml"
grep -Fq 'readonly property real speakingLevel: boundedLevel <= 0.025 ? 0' \
  "$repo_dir/components/VoiceWave.qml"
grep -Fq 'readonly property real voiceBoxLevel: levelMetered ? speakingLevel' \
  "$repo_dir/components/VoiceWave.qml"
grep -Fq 'readonly property bool voiceBoxActive: listening && visualizer === "kitt"' \
  "$repo_dir/components/VoiceWave.qml"
grep -Fq '} else if (root.speaking) {' "$repo_dir/components/VoiceWave.qml"
grep -Fq 'Math.pow((boundedLevel - 0.025) / 0.975, 0.62) * 1.18' \
  "$repo_dir/components/VoiceWave.qml"
grep -Fq 'readonly property int columns: 27' "$repo_dir/components/VoiceWave.qml"
grep -Fq 'readonly property int rows: 5' "$repo_dir/components/VoiceWave.qml"
grep -Fq 'Math.sin(phase * 1.6)' "$repo_dir/components/VoiceWave.qml"
grep -Fq 'var wobble = 0.55 + 0.45 * Math.sin(phase * 6.2 + column * 0.8)' \
  "$repo_dir/components/VoiceWave.qml"
grep -Fq 'readonly property int columns: 72' "$repo_dir/components/SpectrumVisualizer.qml"
grep -Fq 'readonly property int columns: 46' "$repo_dir/components/DotFieldVisualizer.qml"
grep -Fq 'readonly property int rows: 7' "$repo_dir/components/SegmentVisualizer.qml"
grep -Fq 'function sweepX(offset)' "$repo_dir/components/BumperVisualizer.qml"
grep -Fq 'Protocol.normalizedVoiceVisualizer(visualizer) || "kitt"' \
  "$repo_dir/components/ListeningVisualizer.qml"
grep -Fq 'width: Math.min(parent.width * 0.72, Style.space(820))' \
  "$repo_dir/components/VoiceNode.qml"
grep -Fq 'interval: 2800' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'running: root.phase === "thinking" && root.motionEnabled' \
  "$repo_dir/components/VoiceNode.qml"
grep -Fq 'readonly property bool thinkingPhraseRunning: thinkingPhraseTimer.running' \
  "$repo_dir/components/VoiceNode.qml"
grep -Fq 'StatePhrases.thinkingAt(thinkingPhraseIndex)' \
  "$repo_dir/components/VoiceNode.qml"
grep -Fq 'readonly property string captionDetail:' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'id: scannerTravel' "$repo_dir/components/ThinkingScanner.qml"
grep -Fq 'property: "progress"; from: 0; to: 1' \
  "$repo_dir/components/ThinkingScanner.qml"
grep -Fq 'property: "progress"; from: 1; to: 0' \
  "$repo_dir/components/ThinkingScanner.qml"
grep -Fq 'source: scannerGlowSource' "$repo_dir/components/ThinkingScanner.qml"
grep -Fq 'onMotionEnabledChanged: {' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'readonly property bool rotatingActivityStatus:' "$repo_dir/Panel.qml"
grep -Fq 'onRotatingActivityStatusChanged:' "$repo_dir/Panel.qml"
grep -Fq 'text: root.activityStatusText' "$repo_dir/Panel.qml"
grep -Fq 'StatePhrases.thinkingAt(0)' "$repo_dir/tests/visual-preview.qml"
grep -Fq 'StateColor.forPhase' "$repo_dir/components/AnswerCurtain.qml"
grep -Fq 'id: answerScroll' "$repo_dir/components/AnswerCurtain.qml"
grep -Fq 'contentHeight: answerContent.implicitHeight' \
  "$repo_dir/components/AnswerCurtain.qml"
grep -Fq 'boundsBehavior: Flickable.StopAtBounds' \
  "$repo_dir/components/AnswerCurtain.qml"
grep -Fq 'interactive: contentHeight > height' \
  "$repo_dir/components/AnswerCurtain.qml"
grep -Fq 'item: card' \
  "$repo_dir/components/AnswerCurtain.qml"
grep -Fq 'colorizationColor: root.accent' "$repo_dir/components/ActivityFilament.qml"
grep -Fq 'import QtQuick.Effects' "$repo_dir/components/ResponseActivityBorder.qml"
grep -Fq 'import QtQuick.Shapes' "$repo_dir/components/ResponseActivityBorder.qml"
grep -Fq 'id: perimeterTravel' "$repo_dir/components/ResponseActivityBorder.qml"
grep -Fq 'loops: Animation.Infinite' "$repo_dir/components/ResponseActivityBorder.qml"
grep -Fq 'objectName: "responseActivityBloom"' "$repo_dir/components/ResponseActivityBorder.qml"
grep -Fq 'blurMax: root.glowBlurMax' "$repo_dir/components/ResponseActivityBorder.qml"
grep -Fq 'blurMultiplier: 1.1' "$repo_dir/components/ResponseActivityBorder.qml"
grep -Fq 'colorizationColor: root.accent' "$repo_dir/components/ResponseActivityBorder.qml"
test "$(grep -Fc 'strokeColor: root.accent' "$repo_dir/components/ResponseActivityBorder.qml")" -eq 1
test "$(grep -Fc 'dashOffset: (1 - root.phase) * root.trackPerimeter' \
  "$repo_dir/components/ResponseActivityBorder.qml")" -eq 1
test "$(grep -Ec '(^|[^[:alnum:]_.])Shape \{' \
  "$repo_dir/components/ResponseActivityBorder.qml")" -eq 1
test "$(grep -Fc 'MultiEffect {' "$repo_dir/components/ResponseActivityBorder.qml")" -eq 1
grep -Fq 'source: runnerGlowSource' "$repo_dir/components/ResponseActivityBorder.qml"
if ! awk '
  /^  Shape \{/ { inside = 1; next }
  /^  [A-Z]/ { inside = 0 }
  inside && /^    visible: false([[:space:]]|$)/ { hidden = 1 }
  END { if (!hidden) exit 1 }
' "$repo_dir/components/ResponseActivityBorder.qml"; then
  printf 'OmaPilot perimeter source Shape must stay hidden behind the blur\n' >&2
  exit 1
fi
if grep -Eq 'responseActivityCore|id: runnerCore|coreSpan' \
    "$repo_dir/components/ResponseActivityBorder.qml"; then
  printf 'OmaPilot perimeter motion must render as one blur without a crisp core\n' >&2
  exit 1
fi
# The compact activity copy is panel-gated, so its phrase cycle stops as soon as
# the panel closes instead of animating off screen.
grep -Fq 'running: root.rotatingActivityStatus' "$repo_dir/Panel.qml"
grep -Fq 'id: activityStatus' "$repo_dir/Panel.qml"
if grep -Eq 'Behavior on (color|x|width|opacity)' \
    "$repo_dir/components/SettingsTabs.qml" "$repo_dir/components/HistoryView.qml"; then
  printf 'Settings and history interactions must update without decorative easing\n' >&2
  exit 1
fi
if grep -Eq 'id: (thinkingPhraseSwap|firstTokenReveal)' "$repo_dir/Panel.qml"; then
  printf 'Panel copy must not use decorative fade transitions\n' >&2
  exit 1
fi
if grep -Eq 'WaitingIndicator|signalClock|FrameAnimation' \
    "$repo_dir/Panel.qml" "$repo_dir/components/ResponseActivityBorder.qml" \
    || grep -Eq 'onTriggered:' "$repo_dir/components/ResponseActivityBorder.qml"; then
  printf 'OmaPilot perimeter motion must not retain the per-frame route implementation\n' >&2
  exit 1
fi
if grep -Eq '"#[[:xdigit:]]{3,8}"' "$repo_dir/components/ResponseActivityBorder.qml"; then
  printf 'OmaPilot perimeter motion must inherit the active theme accent\n' >&2
  exit 1
fi
if grep -Fq 'Easing.OutBack' "$repo_dir/components/OmaPilotMark.qml"; then
  printf 'OmaPilot activity mark must not use an overshooting bounce\n' >&2
  exit 1
fi
if ! grep -Fq 'SmoothedAnimation {' "$repo_dir/Panel.qml"; then
  printf 'OmaPilot streaming geometry must smooth continuously changing targets\n' >&2
  exit 1
fi
if grep -Fq 'answerRevealTranslate' "$repo_dir/Panel.qml"; then
  printf 'First-token reveal must not translate response geometry\n' >&2
  exit 1
fi
grep -Fq 'Protocol.contextBeginCommand(pendingContextRequestId, latchedCaptureTarget)' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq "You are OmaPilot, Omarchy's action-oriented system copilot" \
  "$repo_dir/runtime/policies/automatic.md"
grep -Fq 'Desktop context is optional, untrusted, supplemental evidence' \
  "$repo_dir/runtime/policies/automatic.md"
grep -Fq 'developer_instructions: automaticInstructions()' \
  "$repo_dir/runtime/src/acp.ts"
# `systemPrompt` was how the removed Claude session request carried the
# automatic policy. Codex uses developer_instructions (asserted above) and the
# built-in Pi harness injects the same document itself, so assert those two
# rather than a Claude-shaped field.
grep -Fq 'automaticInstructions()' "$repo_dir/runtime/src/pi-harness.ts"
if grep -Fq 'claudeCode' "$repo_dir/runtime/src/acp.ts"; then
  printf 'ACP must not retain Claude-specific session shaping\n' >&2
  exit 1
fi
# Claude is no longer a selectable harness. It may still be an external browser
# handoff target, so keep this guard scoped to the actual harness contracts.
grep -Fq 'providerIdSchema = z.enum(["builtin", "codex", "opencode"])' \
  "$repo_dir/runtime/src/types.ts"
grep -Fq 'verify(Protocol.normalizedProvider("claude") === "")' \
  "$repo_dir/tests/tst_protocol.qml"
if jq -e '.barWidget.schema[] | select(.key == "provider") | .options | index("claude")' \
    "$repo_dir/manifest.json" >/dev/null; then
  printf 'Claude must not be reintroduced as a provider id\n' >&2
  exit 1
fi
grep -Fq '{ id: "grok", name: "Grok", piProviderIds: ["xai"] }' "$repo_dir/runtime/src/pi-harness.ts"
grep -Fq 'xai: () => xaiOAuth' "$repo_dir/runtime/src/pi-harness.ts"
# Registering an OpenAI-compatible endpoint must never persist a credential and
# must never shadow a first-party provider.
grep -Fq 'openai-responses' "$repo_dir/runtime/src/custom-providers.ts"
grep -Fq 'RESERVED_IDS' "$repo_dir/runtime/src/custom-providers.ts"
grep -Fq 'Plain http is only allowed for localhost or Tailscale .ts.net endpoints' "$repo_dir/runtime/src/custom-providers.ts"
grep -Fq 'type: "custom_provider_saved"' "$repo_dir/runtime/src/broker.ts"
grep -Fq 'type: "custom_provider_tested"' "$repo_dir/runtime/src/broker.ts"
grep -Fq 'property bool customProviderSavePending: false' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'readonly property bool providerReady: initialized && providerAvailable(provider)' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'readonly property bool canSubmit: providerReady && !continuationBlocked && !busy' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'continuationProvider = currentChatId !== "" ? historicalProvider : ""' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'Protocol.historyContinuationBlocked(' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'if (!providerReady || continuationBlocked || busy) return false' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'if (!OmaPilot.OmaPilotStore.submit(spoken))' "$repo_dir/Ambient.qml"
# The broker's Voxtype OSD switch is a separate config-write boundary from the
# opt-in hotkey helper. It must stay a single-key, comment-preserving,
# backed-up, user-initiated edit, and the exception must stay documented.
grep -Fq '.omapilot.bak' "$repo_dir/runtime/src/voxtype-osd.ts"
grep -Fq 'One separate, narrowly scoped exception exists for Voxtype' \
  "$repo_dir/docs/architecture.md"
if grep -Eq 'writeFileSync\(configPath' "$repo_dir/runtime/src/voxtype-osd.ts"; then
  printf 'Voxtype config must be replaced atomically, not written in place\n' >&2
  exit 1
fi
if grep -Eq '^[[:space:]]+apiKey[[:space:]]*:' "$repo_dir/runtime/src/custom-providers.ts"; then
  printf 'Custom provider definitions must not persist credentials\n' >&2
  exit 1
fi
grep -Fq 'instructions: [automaticInstructionPath()]' \
  "$repo_dir/runtime/src/providers.ts"
grep -Fq 'runtime/policies/automatic.md' "$repo_dir/scripts/package-runtime.sh"
grep -Fq 'runtime/dist/capability-mcp.js' "$repo_dir/scripts/package-runtime.sh"
if grep -Fq 'Animation.Infinite' "$repo_dir/Panel.qml"; then
  printf 'Panel-owned transitions must remain finite\n' >&2
  exit 1
fi
grep -Fq 'OmaPilot.ErrorNotice {' "$repo_dir/Panel.qml"
grep -Fq 'onDetailsRequested: root.openErrorDetails()' "$repo_dir/Panel.qml"
grep -Fq 'OmaPilot.ErrorDetailsView {' "$repo_dir/Panel.qml"
grep -Fq 'visible: root.viewMode === "error"' "$repo_dir/Panel.qml"
grep -Fq 'errorDetails = Protocol.normalizedError(event, statusMessage)' \
  "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'readonly property bool opened:' "$repo_dir/BarWidget.qml"
grep -Fq 'function closeForPopoutSwitch()' "$repo_dir/BarWidget.qml"
test "$(grep -Fc 'IpcHandler {' "$repo_dir/components/OmaPilotStore.qml")" -eq 1
if grep -Fq 'IpcHandler {' "$repo_dir/BarWidget.qml" \
    || grep -Fq 'IpcHandler {' "$repo_dir/Ambient.qml"; then
  printf 'Only OmaPilotStore may register the plugin IPC target\n' >&2
  exit 1
fi
grep -Fq 'function voiceToggle(): string {' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'signal ipcVoiceToggleRequested()' "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'function onIpcOpenRequested()' "$repo_dir/BarWidget.qml"
grep -Fq 'if (root.routedWidget() === root) root.open()' "$repo_dir/BarWidget.qml"
grep -Fq 'signal ipcOpenRequested()' "$repo_dir/components/OmaPilotStore.qml"
manifest_id="$(jq -r '.id' "$repo_dir/manifest.json")"
grep -Fq "target: \"$manifest_id\"" "$repo_dir/components/OmaPilotStore.qml"
grep -Fq 'bar.findPanelWidget(moduleName)' "$repo_dir/BarWidget.qml"
if grep -Fq 'Accessible.name: plainText' "$repo_dir/components/MarkdownView.qml"; then
  printf 'MarkdownView uses TextEdit.plainText, which is unavailable in Qt Quick\n' >&2
  exit 1
fi

QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input "$repo_dir/tests/tst_protocol.qml" \
  -import "$repo_dir" \
  -import "$omarchy_shell"

QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input "$repo_dir/tests/tst_permission_focus.qml" \
  -import "$repo_dir" \
  -import "$omarchy_shell"

QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input "$repo_dir/tests/tst_panel_keyboard_navigation.qml" \
  -import "$repo_dir" \
  -import "$omarchy_shell"

QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input "$repo_dir/tests/tst_history_keyboard.qml" \
  -import "$repo_dir" \
  -import "$omarchy_shell"

QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input "$repo_dir/tests/tst_presentation.qml" \
  -import "$repo_dir" \
  -import "$omarchy_shell"

QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input "$repo_dir/tests/tst_state_color.qml" \
  -import "$repo_dir" || fail "state colour tests failed"

QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input "$repo_dir/tests/tst_state_phrases.qml" \
  -import "$repo_dir" || fail "state phrase tests failed"

QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input "$repo_dir/tests/tst_session_lifecycle.qml" \
  -import "$repo_dir" || fail "session lifecycle tests failed"

QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input "$repo_dir/tests/tst_quick_actions.qml" \
  -import "$repo_dir" \
  -import "$omarchy_shell"

smoke_root="$(mktemp -d)"
cp "$repo_dir/tests/smoke.qml" "$smoke_root/shell.qml"
cp "$repo_dir/Ambient.qml" "$repo_dir/BarWidget.qml" \
  "$repo_dir/ContextCaptureOverlay.qml" "$repo_dir/Panel.qml" "$smoke_root/"
cp -a "$repo_dir/components" "$smoke_root/components"
cp -a "$repo_dir/assets" "$smoke_root/assets"
cp -a "$omarchy_shell/Commons" "$omarchy_shell/Ui" "$smoke_root/"

OMAPILOT_BROKER_PATH=/usr/bin/false QT_QPA_PLATFORM=wayland \
  timeout 5s quickshell --no-duplicate --path "$smoke_root" --no-color \
  >"$smoke_root/output.log" 2>&1
if grep -Eq "smoke loader failed|overlay smoke loader failed|Failed to load|Type .* unavailable|Cannot assign|Handler was registered but will not be used" "$smoke_root/output.log"; then
  cat "$smoke_root/output.log"
  exit 1
fi

cp "$repo_dir/tests/ambient-session-lifecycle-probe.qml" "$smoke_root/shell.qml"
if ! OMAPILOT_BROKER_PATH=/usr/bin/false QT_QPA_PLATFORM=wayland \
    timeout 5s quickshell --no-duplicate --path "$smoke_root" --no-color \
    >"$smoke_root/ambient-session-lifecycle.log" 2>&1; then
  cat "$smoke_root/ambient-session-lifecycle.log"
  exit 1
fi
if grep -Eq "omapilot ambient session lifecycle probe failed|Failed to load|Type .* unavailable|Cannot assign|TypeError|ReferenceError" \
    "$smoke_root/ambient-session-lifecycle.log" \
    || ! grep -Fq 'OMAPILOT_AMBIENT_SESSION_LIFECYCLE_PROBE_OK' \
      "$smoke_root/ambient-session-lifecycle.log"; then
  cat "$smoke_root/ambient-session-lifecycle.log"
  exit 1
fi

cp "$repo_dir/tests/settings-server-save-probe.qml" "$smoke_root/shell.qml"
if ! QT_QPA_PLATFORM=offscreen timeout 5s quickshell --no-duplicate \
    --path "$smoke_root" --no-color >"$smoke_root/server-save.log" 2>&1; then
  cat "$smoke_root/server-save.log"
  exit 1
fi
if grep -Eq "omapilot server save probe failed|Failed to load|Type .* unavailable|Cannot assign|TypeError|ReferenceError" \
    "$smoke_root/server-save.log" \
    || ! grep -Fq 'OMAPILOT_SERVER_SAVE_PROBE_OK' "$smoke_root/server-save.log"; then
  cat "$smoke_root/server-save.log"
  exit 1
fi

cp "$repo_dir/tests/response-activity-border-probe.qml" "$smoke_root/shell.qml"
if ! QT_QPA_PLATFORM=offscreen timeout 5s quickshell --no-duplicate \
    --path "$smoke_root" --no-color >"$smoke_root/motion.log" 2>&1; then
  cat "$smoke_root/motion.log"
  exit 1
fi
if grep -Eq "omapilot motion probe failed|Failed to load|Type .* unavailable|Cannot assign|TypeError" \
    "$smoke_root/motion.log" || ! grep -Fq 'OMAPILOT_MOTION_PROBE_OK' "$smoke_root/motion.log"; then
  cat "$smoke_root/motion.log"
  exit 1
fi

cp "$repo_dir/tests/voice-node-lifecycle-probe.qml" "$smoke_root/shell.qml"
if ! QT_QPA_PLATFORM=wayland timeout 5s quickshell --no-duplicate \
    --path "$smoke_root" --no-color >"$smoke_root/voice-node-lifecycle.log" 2>&1; then
  cat "$smoke_root/voice-node-lifecycle.log"
  exit 1
fi
if grep -Eq "omapilot voice node lifecycle probe failed|Failed to load|Type .* unavailable|Cannot assign|TypeError" \
    "$smoke_root/voice-node-lifecycle.log" \
    || ! grep -Fq 'OMAPILOT_VOICE_NODE_LIFECYCLE_PROBE_OK' "$smoke_root/voice-node-lifecycle.log"; then
  cat "$smoke_root/voice-node-lifecycle.log"
  exit 1
fi

cp "$repo_dir/tests/state-light-bar-lifecycle-probe.qml" "$smoke_root/shell.qml"
if ! QT_QPA_PLATFORM=offscreen timeout 5s quickshell --no-duplicate \
    --path "$smoke_root" --no-color >"$smoke_root/state-light-bar-lifecycle.log" 2>&1; then
  cat "$smoke_root/state-light-bar-lifecycle.log"
  exit 1
fi
if grep -Eq "omapilot state light bar lifecycle probe failed|Failed to load|Type .* unavailable|Cannot assign|TypeError" \
    "$smoke_root/state-light-bar-lifecycle.log" \
    || ! grep -Fq 'OMAPILOT_STATE_LIGHT_BAR_LIFECYCLE_PROBE_OK' \
      "$smoke_root/state-light-bar-lifecycle.log"; then
  cat "$smoke_root/state-light-bar-lifecycle.log"
  exit 1
fi

motion_frame_root="$smoke_root/motion-frames"
mkdir -p "$motion_frame_root"
cp "$repo_dir/tests/motion-preview.qml" "$smoke_root/shell.qml"
if ! OMAPILOT_MOTION_FRAME_DIR="$motion_frame_root" QT_QPA_PLATFORM=offscreen \
    timeout 5s quickshell --no-duplicate --path "$smoke_root" --no-color \
    >"$smoke_root/motion-preview.log" 2>&1; then
  cat "$smoke_root/motion-preview.log"
  exit 1
fi
if grep -Eq "omapilot motion preview failed|Failed to load|Type .* unavailable|Cannot assign|TypeError" \
    "$smoke_root/motion-preview.log" \
    || ! grep -Fq 'OMAPILOT_MOTION_PREVIEW_OK' "$smoke_root/motion-preview.log" \
    || [[ $(find "$motion_frame_root" -maxdepth 1 -type f -name 'frame-*.png' | wc -l) -ne 14 ]]; then
  cat "$smoke_root/motion-preview.log"
  exit 1
fi

state_frame_root="$smoke_root/state-frames"
mkdir -p "$state_frame_root"
cp "$repo_dir/tests/state-motion-preview.qml" "$smoke_root/shell.qml"
if ! OMAPILOT_STATE_FRAME_DIR="$state_frame_root" QT_QPA_PLATFORM=offscreen \
    timeout 7s quickshell --no-duplicate --path "$smoke_root" --no-color \
    >"$smoke_root/state-motion-preview.log" 2>&1; then
  cat "$smoke_root/state-motion-preview.log"
  exit 1
fi
if grep -Eq "omapilot state motion preview failed|Failed to load|Type .* unavailable|Cannot assign|TypeError" \
    "$smoke_root/state-motion-preview.log" \
    || ! grep -Fq 'OMAPILOT_STATE_MOTION_PREVIEW_OK' "$smoke_root/state-motion-preview.log" \
    || [[ $(find "$state_frame_root" -maxdepth 1 -type f -name 'state-*.png' | wc -l) -ne 8 ]]; then
  cat "$smoke_root/state-motion-preview.log"
  exit 1
fi

visualizer_frame="$smoke_root/listening-visualizers.png"
cp "$repo_dir/tests/listening-visualizers-preview.qml" "$smoke_root/shell.qml"
if ! OMAPILOT_VISUALIZER_FRAME="$visualizer_frame" QT_QPA_PLATFORM=offscreen \
    timeout 5s quickshell --no-duplicate --path "$smoke_root" --no-color \
    >"$smoke_root/listening-visualizers.log" 2>&1; then
  cat "$smoke_root/listening-visualizers.log"
  exit 1
fi
if grep -Eq "omapilot visualizer preview failed|Failed to load|Type .* unavailable|Cannot assign|TypeError" \
    "$smoke_root/listening-visualizers.log" \
    || ! grep -Fq 'OMAPILOT_VISUALIZER_PREVIEW_OK' "$smoke_root/listening-visualizers.log" \
    || [[ ! -s $visualizer_frame ]]; then
  cat "$smoke_root/listening-visualizers.log"
  exit 1
fi

preview_root="$(mktemp -d)"
preview_output="$repo_dir/screenshots/implementation-omapilot-empty.png"
mkdir -p "$repo_dir/screenshots"
cp "$repo_dir/tests/visual-preview.qml" "$preview_root/shell.qml"
cp -a "$repo_dir/components" "$preview_root/components"
cp -a "$repo_dir/assets" "$preview_root/assets"
cp -a "$omarchy_shell/Commons" "$omarchy_shell/Ui" "$preview_root/"

OMAPILOT_PREVIEW_PATH="$preview_output" QT_QPA_PLATFORM=offscreen \
  timeout 5s quickshell --no-duplicate --path "$preview_root" --no-color \
  >"$preview_root/output.log" 2>&1
if grep -Eq "visual preview failed|Failed to load|Type .* unavailable|Cannot assign|TypeError" \
    "$preview_root/output.log" || [[ ! -s "$preview_output" ]]; then
  cat "$preview_root/output.log"
  exit 1
fi

preview_output="$repo_dir/screenshots/implementation-omapilot-dangerous-settings.png"
OMAPILOT_PREVIEW_STATE=dangerous-settings OMAPILOT_PREVIEW_PATH="$preview_output" \
  QT_QPA_PLATFORM=offscreen timeout 5s quickshell --no-duplicate \
  --path "$preview_root" --no-color >"$preview_root/settings-output.log" 2>&1
if grep -Eq "visual preview failed|Failed to load|Type .* unavailable|Cannot assign|TypeError" \
    "$preview_root/settings-output.log" || [[ ! -s "$preview_output" ]]; then
  cat "$preview_root/settings-output.log"
  exit 1
fi

for preview_state in settings skills-settings voice-settings desktop-settings actions-settings \
    setup-voice setup-hotkeys history waiting streaming error error-details context; do
  preview_output="$repo_dir/screenshots/implementation-omapilot-$preview_state.png"
  OMAPILOT_PREVIEW_STATE="$preview_state" OMAPILOT_PREVIEW_PATH="$preview_output" \
    QT_QPA_PLATFORM=offscreen timeout 5s quickshell --no-duplicate \
    --path "$preview_root" --no-color >"$preview_root/$preview_state-output.log" 2>&1
  if grep -Eq "visual preview failed|Failed to load|Type .* unavailable|Cannot assign|TypeError" \
      "$preview_root/$preview_state-output.log" || [[ ! -s "$preview_output" ]]; then
    cat "$preview_root/$preview_state-output.log"
    exit 1
  fi
done
