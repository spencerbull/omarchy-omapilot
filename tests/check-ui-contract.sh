#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
omarchy_shell="${OMARCHY_PATH:-/home/sbull/omarchy}/shell"
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
  "$repo_dir/components/ContextAttachmentPreview.qml"
  "$repo_dir/components/ErrorDetailsView.qml"
  "$repo_dir/components/ErrorNotice.qml"
  "$repo_dir/components/HistoryView.qml"
  "$repo_dir/components/MarkdownView.qml"
  "$repo_dir/components/OmaPilotHeader.qml"
  "$repo_dir/components/OmaPilotMark.qml"
  "$repo_dir/components/QuickActions.qml"
  "$repo_dir/components/QuickActionEditor.qml"
  "$repo_dir/components/SettingsView.qml"
  "$repo_dir/components/SettingsTabs.qml"
  "$repo_dir/components/ActivityFilament.qml"
  "$repo_dir/components/ResponseActivityBorder.qml"
  "$repo_dir/components/internal/PermissionFocusGuard.qml"
  "$repo_dir/components/internal/PanelKeyboardNavigation.qml"
  "$repo_dir/components/internal/HistoryListKeyboardHandler.qml"
  "$repo_dir/components/QuickchatStore.qml"
  "$repo_dir/components/DesktopContext.qml"
  "$repo_dir/components/Protocol.js"
  "$repo_dir/components/Presentation.js"
  "$repo_dir/components/QuickActions.js"
  "$repo_dir/tests/motion-preview.qml"
)

/usr/lib/qt6/bin/qmllint -I "$omarchy_shell" -I "$repo_dir" "${qml_files[@]}" >/dev/null 2>&1

grep -Fq 'Qt.resolvedUrl("../runtime/bin/quickchat-broker")' \
  "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'Quickshell.env("QUICKCHAT_BROKER_PATH") || bundledBrokerPath' \
  "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'property string configuredProvider: "builtin"' \
  "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'harness: provider' "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'readonly property var modeProviders: Protocol.harnessOptions()' \
  "$repo_dir/components/SettingsView.qml"
grep -Fq 'text: "Open sign-in page"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'sendCommand(Protocol.command("auth_begin", { methodId: selected }))' \
  "$repo_dir/components/QuickchatStore.qml"
if grep -Fq 'PI_CODING_AGENT_DIR' "$repo_dir/components/QuickchatStore.qml"; then
  printf 'Built-in authentication must stay embedded instead of launching Pi\n' >&2
  exit 1
fi
if grep -Fq 'backendSelection' "$repo_dir/components/QuickchatStore.qml"; then
  printf 'Harness selection must not be split into backend and provider settings\n' >&2
  exit 1
fi
grep -Fq 'property bool desktopContextEnabled: true' \
  "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'DesktopContext.snapshot()' "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'Protocol.hasFeature(event.features, "desktop-context")' "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'import Quickshell.Hyprland' "$repo_dir/components/DesktopContext.qml"
grep -Fq 'import Quickshell.Services.Mpris' "$repo_dir/components/DesktopContext.qml"
awk '
  /^[[:space:]]*function / { latched = 0 }
  /Quickchat\.QuickchatStore\.latchDesktopContext\(\)/ { latched = 1 }
  /root\.controller\.show\(\)/ { if (!latched) exit 1; shows += 1 }
  END { if (shows < 3) exit 1 }
' "$repo_dir/Panel.qml"
awk '
  /^[[:space:]]*function / { cleared = 0 }
  /Quickchat\.QuickchatStore\.clearDesktopContextLatch\(\)/ { cleared = 1 }
  /root\.controller\.hide\(\)/ { if (!cleared) exit 1; hides += 1 }
  END { if (hides < 2) exit 1 }
' "$repo_dir/Panel.qml"
awk '
  /function desktopContextForSubmit\(\)/ { inside = 1; gated = 0 }
  inside && /if \(!desktopContextActive\) return null/ { gated = 1 }
  inside && /DesktopContext\.snapshot\(\)/ { if (!gated) exit 1; found = 1; exit }
  END { if (!found) exit 1 }
' "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'if (context && context.activeWindow) latchedActiveWindow = context.activeWindow' \
  "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'if (!changed) return' "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'model = desiredModel' "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'if (providers.length > 0) selectProvider(provider)' \
  "$repo_dir/components/QuickchatStore.qml"
test "$(grep -Fc 'root.pendingPermission = null' "$repo_dir/components/QuickchatStore.qml")" -ge 2
test "$(grep -Fc 'root.permissionQueue = []' "$repo_dir/components/QuickchatStore.qml")" -ge 2
grep -Fq 'signal escapeRequested()' "$repo_dir/components/Composer.qml"
grep -Fq 'Protocol.providerPolicyDescription(root.backend.provider, root.backend.providerPolicy)' "$repo_dir/components/SettingsView.qml"
grep -Fq 'policy.web === "search"' "$repo_dir/components/Protocol.js"
grep -Fq 'policy.web === "approved-command"' "$repo_dir/components/Protocol.js"
if grep -Fq 'ButtonGroup {' "$repo_dir/components/Composer.qml"; then
  printf 'Composer must not expose a capability mode selector\n' >&2
  exit 1
fi
if grep -Fqi 'capability' "$repo_dir/components/Protocol.js" "$repo_dir/components/QuickchatStore.qml"; then
  printf 'QML protocol and store must not expose capability helpers or fields\n' >&2
  exit 1
fi
if grep -Fqi 'local_action' "$repo_dir/Panel.qml" "$repo_dir/components/Protocol.js" "$repo_dir/components/QuickchatStore.qml"; then
  printf 'QML must not expose hardcoded local-action routing\n' >&2
  exit 1
fi
grep -Fq 'visible: !root.backend || root.backend.pendingPermission === null' \
  "$repo_dir/components/Composer.qml"
if grep -Eq 'sandboxed|Device commands stay blocked|sandbox limits stay active' \
  "$repo_dir/Panel.qml" "$repo_dir/components/Protocol.js"; then
  printf 'QML permission copy must not retain unreachable legacy policy branches\n' >&2
  exit 1
fi
grep -Fq 'Review the exact request and choose how long this agent may retain the approval.' \
  "$repo_dir/Panel.qml"
grep -Fq 'readonly property bool popupOpen:' "$repo_dir/components/Composer.qml"
grep -Fq 'var action = Presentation.escapeAction(root.viewMode, composer.popupOpen,' "$repo_dir/Panel.qml"
grep -Fq 'if (action === "close-composer-popup") composer.closePopups()' "$repo_dir/Panel.qml"
grep -Fq 'Quickchat.SettingsView {' "$repo_dir/Panel.qml"
grep -Fq 'visible: root.viewMode === "settings"' "$repo_dir/Panel.qml"
grep -Fq 'settingsView.popupOpen' "$repo_dir/Panel.qml"
# The ambient redesign removed the panel header (logo, tagline, gear). The
# chrome assertions below pin the replacement instead: a borderless hero prompt,
# the shared activity filament, and the single hint row that now carries
# provider identity, permission posture, and the lane shortcuts. Settings and
# history lost their buttons, so their keys must exist or they are unreachable.
if grep -Fq 'Quickchat.OmaPilotHeader {' "$repo_dir/Panel.qml"; then
  printf 'Panel must not reintroduce the OmaPilot header chrome\n' >&2
  exit 1
fi
grep -Fq 'ActivityFilament {' "$repo_dir/components/Composer.qml"
grep -Fq 'id: promptRow' "$repo_dir/components/Composer.qml"
grep -Fq 'font.pixelSize: Style.font.heading' "$repo_dir/components/Composer.qml"
grep -Fq 'sequences: ["Ctrl+H"]' "$repo_dir/Panel.qml"
grep -Fq 'sequences: ["Ctrl+,"]' "$repo_dir/Panel.qml"
grep -Fq 'Presentation.permissionNotice(root.dangerousAutoApprove)' "$repo_dir/Panel.qml"
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
grep -Fq 'visible: Quickchat.QuickchatStore.pendingPermission !== null' "$repo_dir/Panel.qml"
grep -Fq 'Quickchat.QuickActions {' "$repo_dir/Panel.qml"
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
test "$(grep -Fc '&& !Quickchat.QuickchatStore.busy' "$repo_dir/Panel.qml")" -ge 2
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
grep -Fq 'text: "Browser context"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'onDesktopContextRequested:' "$repo_dir/Panel.qml"
grep -Fq 'text: "History"' "$repo_dir/components/HistoryView.qml"
grep -Fq 'ActivityFilament {' "$repo_dir/components/HistoryView.qml"
grep -Fq 'text: root.browserCompanion.relayInstalled === true ? "Repair browser setup" : "Enable browser context"' \
  "$repo_dir/components/SettingsView.qml"
grep -Fq 'onBrowserCompanionInstallRequested:' "$repo_dir/Panel.qml"
grep -Fq 'Protocol.command("browser_companion_install")' "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'Protocol.command("browser_companion_uninstall")' "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'Protocol.command("browser_companion_open_settings", { family: selected })' \
  "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'text: "Open Firefox debugging"' "$repo_dir/components/SettingsView.qml"
grep -Fq 'Accessible.name: "Copy Firefox extension folder path"' \
  "$repo_dir/components/SettingsView.qml"
grep -Fq 'text: root.browserRemoveConfirmation ? "Confirm removal" : "Remove browser context"' \
  "$repo_dir/components/SettingsView.qml"
grep -Fq 'onDangerousAutoApproveRequested:' "$repo_dir/Panel.qml"
awk '
  /function close\(\)/ { inside = 1; cleared = 0 }
  inside && /Quickchat\.QuickchatStore\.clearContextAttachments\(\)/ { cleared = 1 }
  inside && /root\.controller\.hide\(\)/ { if (!cleared) exit 1; found = 1; exit }
  END { if (!found) exit 1 }
' "$repo_dir/Panel.qml"
grep -Fq 'backend.submit(draftText)' \
  "$repo_dir/components/Composer.qml"
grep -Fq 'var autoApprove = configuredDangerousAutoApprove' \
  "$repo_dir/components/QuickchatStore.qml"
if grep -Fq 'tooltipText: "Close Quickchat"' "$repo_dir/Panel.qml" "$repo_dir/components/SettingsView.qml"; then
  printf 'OmaPilot must rely on panel dismissal rather than a redundant close control\n' >&2
  exit 1
fi
grep -Fq 'Presentation.boundedPanelHeight(root.activeNaturalHeight' "$repo_dir/Panel.qml"
grep -Fq 'popup.availableCardHeight * 0.82' "$repo_dir/Panel.qml"
grep -Fq 'id: responseViewport' "$repo_dir/Panel.qml"
grep -Fq 'property bool followLatest: true' "$repo_dir/Panel.qml"
grep -Fq 'onMovementEnded: followLatest = Presentation.isNearBottom(' "$repo_dir/Panel.qml"
grep -Fq 'tooltipText: "Jump to the newest response"' "$repo_dir/Panel.qml"
# The perimeter runner circled the answer card's border. The redesign removed
# that border, so the activity signal moved to the composer's filament. The
# component itself is retained for its motion probe and preview fixtures, but
# the panel must not put a runner back around the response.
if grep -Fq 'Quickchat.ResponseActivityBorder {' "$repo_dir/Panel.qml"; then
  printf 'Panel must not reintroduce the response perimeter runner\n' >&2
  exit 1
fi
grep -Fq 'id: sweepSource' "$repo_dir/components/ActivityFilament.qml"
# Every state must resolve through one mapping rather than hardcoding accent.
grep -Fq 'StateColor.forPhase' "$repo_dir/components/VoiceNode.qml"
grep -Fq 'StateColor.forPhase' "$repo_dir/components/AnswerCurtain.qml"
grep -Fq 'StateColor.forPhase' "$repo_dir/Panel.qml"
grep -Fq 'colorizationColor: root.accent' "$repo_dir/components/ActivityFilament.qml"
grep -Fq 'id: responseStatusSlot' "$repo_dir/Panel.qml"
grep -Fq 'Layout.minimumWidth: Style.space(140)' "$repo_dir/Panel.qml"
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
# Same invariant as before the redesign, on the filament instead of the
# perimeter runner: response motion is gated on the panel actually being open,
# so nothing animates off screen.
grep -Fq 'activityActive: root.responseActivityActive && root.opened' "$repo_dir/Panel.qml"
grep -Fq 'active: root.activityActive' "$repo_dir/components/Composer.qml"
grep -Fq 'id: activityStatus' "$repo_dir/Panel.qml"
if grep -Eq 'WaitingIndicator|signalClock|FrameAnimation|onTriggered:' \
    "$repo_dir/Panel.qml" "$repo_dir/components/ResponseActivityBorder.qml"; then
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
  "$repo_dir/components/QuickchatStore.qml"
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
# Claude is no longer a selectable harness anywhere in the product.
if grep -Fq '"claude"' "$repo_dir/runtime/src/types.ts" "$repo_dir/components/Protocol.js"; then
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
grep -Fq 'property bool customProviderSavePending: false' "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'readonly property bool providerReady: initialized && providerAvailable(provider)' "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'readonly property bool canSubmit: providerReady && !continuationBlocked && !busy' "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'continuationProvider = currentChatId !== "" ? historicalProvider : ""' "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'Protocol.historyContinuationBlocked(' "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'if (!providerReady || continuationBlocked || busy) return false' "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'if (!OmaPilot.QuickchatStore.submit(spoken))' "$repo_dir/Ambient.qml"
# The Voxtype OSD switch is the one place OmaPilot writes another tool's config.
# It must stay a single-key, comment-preserving, backed-up, user-initiated edit,
# and the exception must stay documented.
grep -Fq '.omapilot.bak' "$repo_dir/runtime/src/voxtype-osd.ts"
grep -Fq 'One narrowly scoped exception exists for Voxtype' "$repo_dir/docs/architecture.md"
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
if grep -Fq 'Animation.Infinite' "$repo_dir/Panel.qml"; then
  printf 'Panel-owned transitions must remain finite\n' >&2
  exit 1
fi
grep -Fq 'Quickchat.ErrorNotice {' "$repo_dir/Panel.qml"
grep -Fq 'onDetailsRequested: root.openErrorDetails()' "$repo_dir/Panel.qml"
grep -Fq 'Quickchat.ErrorDetailsView {' "$repo_dir/Panel.qml"
grep -Fq 'visible: root.viewMode === "error"' "$repo_dir/Panel.qml"
grep -Fq 'errorDetails = Protocol.normalizedError(event, statusMessage)' \
  "$repo_dir/components/QuickchatStore.qml"
grep -Fq 'readonly property bool opened:' "$repo_dir/BarWidget.qml"
grep -Fq 'function closeForPopoutSwitch()' "$repo_dir/BarWidget.qml"
test "$(grep -Fc 'IpcHandler {' "$repo_dir/components/QuickchatStore.qml")" -eq 1
if grep -Fq 'IpcHandler {' "$repo_dir/BarWidget.qml"; then
  printf 'BarWidget must not register one IPC target per monitor\n' >&2
  exit 1
fi
grep -Fq 'function onIpcOpenRequested()' "$repo_dir/BarWidget.qml"
grep -Fq 'if (root.routedWidget() === root) root.open()' "$repo_dir/BarWidget.qml"
grep -Fq 'signal ipcOpenRequested()' "$repo_dir/components/QuickchatStore.qml"
manifest_id="$(jq -r '.id' "$repo_dir/manifest.json")"
grep -Fq "target: \"$manifest_id\"" "$repo_dir/components/QuickchatStore.qml"
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
  -input "$repo_dir/tests/tst_quick_actions.qml" \
  -import "$repo_dir" \
  -import "$omarchy_shell"

smoke_root="$(mktemp -d)"
cp "$repo_dir/tests/smoke.qml" "$smoke_root/shell.qml"
cp "$repo_dir/BarWidget.qml" "$repo_dir/ContextCaptureOverlay.qml" "$repo_dir/Panel.qml" "$smoke_root/"
cp -a "$repo_dir/components" "$smoke_root/components"
cp -a "$repo_dir/assets" "$smoke_root/assets"
cp -a "$omarchy_shell/Commons" "$omarchy_shell/Ui" "$smoke_root/"

QUICKCHAT_BROKER_PATH=/usr/bin/false QT_QPA_PLATFORM=wayland \
  timeout 5s quickshell --no-duplicate --path "$smoke_root" --no-color \
  >"$smoke_root/output.log" 2>&1
if grep -Eq "smoke loader failed|overlay smoke loader failed|Failed to load|Type .* unavailable|Cannot assign" "$smoke_root/output.log"; then
  cat "$smoke_root/output.log"
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

for preview_state in settings actions-settings history waiting streaming error error-details context; do
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
