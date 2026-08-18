# Architecture and host contract

## Omarchy ownership

Quickchat is one third-party `bar-widget`; it is not a replacement bar, panel plugin, service plugin, or second Quickshell process. Its repository-root `manifest.json` declares schema version 1 and the relative `BarWidget.qml` entrypoint. Omarchy owns discovery, enabled state, placement, settings persistence, theme services, panel coordination, and hot reload.

The widget follows the current Quattro host contract:

- installation is a plain git clone under `~/.config/omarchy/plugins/io.github.spencerbull.quickchat`;
- enablement adds one inline entry to `bar.layout.right` in `shell.json`;
- the host injects `settings`, `manifest`, `shell`, `pluginRegistry`, and `barWidgetRegistry` where supported;
- preferences are inline widget settings—there is no second configuration authority;
- colors, type, borders, radii, and motion come from public `qs.Commons` and `qs.Ui` theme roles;
- the widget coordinates one nested Omarchy `Panel` through the same open/close/anchor/popout behavior used by first-party bar widgets.
- one monitor instance conditionally owns the direct Quickchat IPC target, then
  routes panel actions through Quattro's focused-monitor bar-widget resolver;
  ownership follows the host's reassigned module list across monitor changes.

Quickchat does not edit `shell.json`, Omarchy sources, Hyprland configuration, Voxtype configuration, or Herdr configuration directly.

## Process boundary

The UI starts a separate Quickchat broker and communicates using newline-delimited JSON on stdin/stdout. The broker owns selected-harness discovery and authentication readiness, the embedded Pi lifecycle, ACP lifecycle, permission handling, streaming, cancellation, validation, history, and optional integration commands. Provider stderr is diagnostic input and must never be forwarded to persisted history without redaction.

The reviewed plugin revision contains self-contained broker and adapter bundles usable immediately after a plain clone. Release builds package those tracked bundles into a deterministic, checksum-addressed `linux-x86_64` archive with lockfile-derived SBOM and provenance. Omarchy itself still performs no install hook. Contributors use `npm ci && npm run build` to reproduce checked-in bundles; missing or incompatible runtimes fail closed.

## Runtime command/event contract

One compact JSON object is sent per line; embedded newlines remain JSON escapes. Each command has an `id`. Every correlated event repeats that `id`; asynchronous readiness events may omit it.

The UI sends commands whose `type` is one of `initialize`, `submit`, `context_begin`, `context_capture`, `context_cancel`, `context_discard`, `cancel`, `permission_response`, `dictation_start`, `dictation_stop`, `dictation_cancel`, `copy`, `open_link`, `load_image`, `continue_in_herdr`, `history_list`, `history_delete`, `history_clear`, or `shutdown`.

The broker emits events whose `type` is one of `ready`, `providers`, `state`, `content`, `context_ready`, `context_attachment`, `permission`, `permission_closed`, `image`, `complete`, `error`, `dictation`, `history`, `herdr`, `link`, or `copied`. The broker's protocol tests are authoritative for exact fields and version negotiation.

The broker's internal run contract is the normalization boundary, not the policy
boundary. Initialization selects exactly one harness: the embedded Pi runtime
or one ACP harness. Discovery failure never switches harnesses. The submit
command contains provider/model/question, an optional prior chat identity for
same-harness continuation, plus an optional versioned desktop
snapshot and up to four opaque context-attachment selections. QML latches the active app and
its capture rectangle immediately before the panel takes focus
and synchronously reads the current app/workspace/media inventory from
Quickshell's public Hyprland and MPRIS objects at submit time; it does not poll
`hyprctl` or create a second desktop service. The broker independently validates
field counts, lengths, and control characters, then frames the snapshot as
untrusted observational JSON before the authoritative user request. It sends
the combined prompt to the selected ACP session but stores only the original
question in Quickchat history. The Built-in runtime stores Pi sessions beneath
the Quickchat XDG state root and resolves continuation only through a validated
saved chat and session identity. Native Herdr resume therefore inherits the Pi
conversation and uses a pane-scoped OmaPilot configuration environment; the
transcript fallback remains available when a native harness cannot resume.

## Explicit context clips

OmaPilot is a multi-kind `bar-widget` and `overlay` plugin. The panel asks the
broker to begin a capture, and the broker selects the monitor containing the
current compositor cursor. A click is resolved against the current Hyprland
client geometries, excluding OmaPilot's own Quickshell surface, so panel focus
cannot replace the user's intended target. The broker focuses that resolved
window and either arms its browser companion or captures the validated window
geometry. A drag remains an exact monitor-local region. The overlay hides for
two compositor frames before asking the broker to invoke `grim`, so OmaPilot
chrome is not present in the pixels.

The broker fully decodes and normalizes every image through the existing image
policy. If local Tesseract is available, word boxes are hit-tested at the click
point and expanded to their OCR paragraph. The resulting attachment may offer
Text, Screenshot, or Text + screenshot. The thumbnail remains a local preview;
only the representation IDs selected in the composer cross the submit boundary.
QML never sends image paths, base64, OCR payloads, or arbitrary HTML back to the
broker. The broker resolves opaque UUIDs against its in-memory attachment map,
constructs ACP text/image blocks, and deletes the cached input image after
submit or explicit removal.

The representation contract implements `element` through the separately
installed browser companion. The broker owns a mode-0600 Unix socket below
`$XDG_RUNTIME_DIR/quickchat`; browser-native relay processes connect that socket
to an allowlisted extension ID through the browser's native-messaging transport.
The relay exposes only versioned hello, probe, arm, result, cancel, and error
messages. It is not a general browser command channel.

After the overlay click resolves a browser window beneath the cursor, the broker
maps its app ID to the Chromium or Firefox family and probes connected companion
sessions. A permitted content script returns active-page title and URL only for
that explicit request. The broker normalizes the compositor title, chooses one
matching session, and arms only that page. Quickshell closes rather than
intercepting the next click; the content script performs browser-native hit
testing, visibly highlights the candidate, and captures on click or cancels on
Escape. If no permitted picker responds, the normal Quickshell screenshot/OCR
capture remains authoritative.

The extension records the exact tab ID that answered each probe and rejects a
result from another tab or frame. The broker independently records the selected
native-relay session and ignores a result with the same request ID from any
other session. Editable roots and descendants are pruned before serialization;
editable accessible-name fallbacks and selections rooted in editable content
are not collected.

The broker validates the returned page and semantic-node schema, caps the tree
again to 80 nodes, depth four, 12 KiB visible text, and a 32 KiB serialized
element, strips URL credentials/query/fragment, and captures the already
latched browser window through the existing image policy after the picker has
disappeared. The attachment therefore offers Element, Text, Screenshot, or a
supported pair without sending DOM through QML. The UI still submits only an
opaque attachment UUID and representation IDs.

Site permission is granted from the extension popup because a desktop-shell
gesture cannot activate browser `activeTab` authority. Permission is optional,
origin-scoped, and registers the inert picker content script only for enabled
origins. It does not collect page metadata until an explicit broker probe.

Settings exposes broker-reported relay and per-family connection readiness. An
explicit **Enable browser context** action asks the broker to run only the
repository-owned companion installer; QML never constructs a command or edits
browser configuration. The action registers a user-local native-messaging host
and enables the bundled unpacked Chromium build in detected Omarchy browser flag
files. It remains separate from normal plugin installation, requires a browser
restart, and cannot grant origin permission on the user's behalf. An expandable
setup section opens the fixed Chromium extensions or Firefox debugging page and
copies the broker-reported bundled folder path, so Firefox/Zen and Chromium
fallback setup can be completed without reconstructing a shell command.

The matching two-step **Remove browser context** action asks the broker to run
the repository-owned uninstaller, disconnect active relay sessions, and remove
the user-local host, browser registrations, and extension flags. Open browsers
must restart to unload an extension process already in memory. Omarchy's plugin
manager intentionally executes no plugin lifecycle hooks, so this cleanup must
run before the plugin directory is removed; automatic cleanup on
`omarchy plugin remove` requires a future host-owned lifecycle contract.

The broker derives one automatic,
fail-closed policy for that provider. Codex keeps the pinned adapter's read-only,
on-request mode, disables native web search, and exposes only its strictly validated
shell/unified-exec and skill-search features. It may read any user-readable host file without
asking; tool output is sent to Codex and may be retained in the saved answer.
Each broader-access request is bound to a broker nonce. The UI preserves the
provider's allow/reject option identities and distinguishes session labels from
durable labels; approval may run commands with current-user device and network
authority for the scope stated by that option. Claude copies bounded, regular-file
installed skill trees into a per-turn local plugin with MCP discovery disabled,
then uses a disposable
workspace that dynamically denies every existing top-level host path except
system executable/library roots, hides credential-bearing environment variables,
blocks direct process network access and WebFetch, confines writes to per-turn
scratch, and allows WebSearch. Commands inside that boundary may run
automatically. A Claude command that needs device authority accepts the
broker-bound choices offered by its adapter. Allowing it runs outside the
disposable sandbox with the current user's full device,
network, host-file, and process-environment authority. OpenCode automatically permits
only its exact skill and websearch identities. Its native bash permission is
fixed to `ask`; the broker correlates the pending execution, permission request,
decision, and subsequent updates by tool-call ID before allowing completion.
Every other OpenCode tool remains denied.
Unclassified tool kinds fail closed. Raw tool requests,
decisions, updates, and outputs remain ephemeral, while the completed answer may
contain tool-derived text and is retained like any other answer. Continue in Herdr intentionally leaves that one-shot boundary and
hands the resumable session or transcript to Herdr, which becomes the authority
for native-agent permissions and lifecycle.

The broker does not classify prompt text into action-specific code paths.
Questions and action requests use the same ACP submission contract; the
selected harness decides whether a tool is needed under its fixed policy, and
the broker only mediates structured, request-bound permission events.
One checked-in instruction is supplied through Codex developer instructions,
Claude's system prompt plus `skills: all`, and OpenCode's instruction-file
configuration. It directs providers to use relevant installed skills and never
claim an action completed without a successful performing tool result.

## Compatibility rule

The protocol and release metadata are versioned independently of the manifest schema. Protocol 2 removes user-selected capability fields and makes the broker's automatic provider policy authoritative; legacy stored protocol-1 chats remain readable and are projected into the protocol-2 public shape. The plugin must show an actionable incompatibility error when the cached runtime cannot negotiate its supported protocol; it must not guess at provider output or silently broaden permissions.
