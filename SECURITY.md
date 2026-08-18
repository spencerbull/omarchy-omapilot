# Security policy

## Supported versions

Security fixes are provided for the current OmaPilot release.

## Trust model

Omarchy plugins run unsandboxed inside the long-lived `omarchy-shell` process. Review OmaPilot before enabling it. OmaPilot minimizes that authority by delegating provider traffic to a separate broker process and starting each agent with one provider-specific, fail-closed automatic policy.

- The embedded Pi harness loads declarative skills, context files, and named
  agent profiles from the standard `~/.agents` roots. It does not
  auto-load executable Pi extensions. Read, grep, find, and list tools use the
  current user's read authority. Every Pi bash, edit, and write call—including
  calls made by a named agent—is intercepted before execution and requires the
  broker's reviewed decision. Session and durable Pi grants match only the exact
  request and working directory; durable records contain hashes, not commands.
  Named agents cannot delegate recursively.

- Codex starts in read-only, on-request mode with native web search disabled and only the
  strictly validated shell/unified-exec and skill-search features. It may read any file the current user can
  read without asking. Tool output is sent to Codex and may be retained in the
  saved answer. A request for broader access pauses behind the adapter-normalized
  command and working directory, and its provider-native approval choices are
  exposed without collapsing their option identities.
  Approval can execute the command outside the read-only sandbox with the
  current user's authority, including host reads, state changes, and network
  access; the UI states this explicitly. When the user explicitly enables
  **Dangerous auto-approve**, each request may select the normalized request's
  exact provider-native allow-once option without prompting. It never selects a
  session or durable grant.
- Claude loads installed skills through a per-turn plugin copy with MCP discovery
  disabled. Internal symlinks, oversized trees, and non-regular entries are
  skipped. It runs inside a disposable workspace that denies
  every existing top-level host path except system executable/library roots,
  hides credential-bearing environment variables, and confines writes to
  per-turn scratch. WebSearch is available, while WebFetch and direct process
  network access remains blocked. Commands inside that fixed boundary may run
  automatically. A command that cannot run inside that boundary may proceed
  only through a broker-bound choice supplied by the Claude adapter. Approving
  it explicitly lets it run outside the disposable sandbox with the
  current user's full process environment and device authority, including host
  reads, writes, credential-bearing environment variables, and network access.
- OpenCode may load its positively identified skill tool and use websearch
  automatically. Its external-directory check is allowed only as a prerequisite
  to a separately reviewed shell request; `bash` remains `ask`, and execution
  updates must correlate with the exact approved ACP tool-call ID. Every other
  OpenCode permission remains denied.
- Oversized requests and control or bidirectional-display characters fail
  closed rather than being truncated.
- Dangerous auto-approval remains behind the provider's existing
  device-approval policy and the same execute-kind, complete-input, and
  allow-once normalization. Missing or unreviewable choices are cancelled;
  blocked providers do not gain tool authority from this setting.
- Arbitrary MCP, browser/computer control, unclassified requests, and requests
  without an inspectable target are denied. Codex may edit, delete, move, or
  otherwise mutate user-accessible state only after an explicit provider-native
  approval whose displayed label defines its duration.
- Built-in authentication is resolved in memory by Pi from environment
  variables or `${XDG_CONFIG_HOME:-$HOME/.config}/omapilot/auth.json`; authentication for an explicitly selected ACP harness remains in that
  installed harness. OmaPilot must not log, copy, or persist credential output.
  Credential entries may intentionally reference user-configured commands, so
  `auth.json` is trusted executable configuration and must be user-owned.
- Adapter bundles are generated from exact package-lock versions and reviewed as tracked files in the same Git commit as their source. Published release archives add SHA-256 verification, provenance, and an SBOM; the runtime does not download or replace adapters.
- Remote images require a user action and are subject to scheme, redirect, address, MIME, byte-size, complete decode, pixel-area, and cache-quota checks before Quickshell sees them.
- Context capture is an explicit overlay gesture. The active target is latched
  before OmaPilot takes focus, monitor and region geometry are validated by the
  broker, and the overlay is hidden before `grim` runs. Captured images pass the
  same complete-decode, byte, dimension, pixel-area, and cache policy as remote
  images. Optional OCR is local and bounded; only the paragraph hit beneath the
  pointer is offered. Password-like targets are blocked conservatively.
- The composer receives only an opaque attachment UUID, bounded presentation
  metadata, and a broker-issued local thumbnail URL. Submit carries only that
  UUID and selected representation IDs. It cannot provide an image path,
  base64 payload, OCR text, or raw DOM. The broker resolves the retained value,
  frames text and pixels as untrusted observational data, and deletes input
  images after submission, explicit removal, new chat, or ordinary panel
  dismissal. Provider-native sessions may retain the
  selected clip even though OmaPilot does not add it to chat JSON.
- The optional browser companion is separately and reversibly installed. Its
  extension has no `tabs`, `history`, `debugger`, cookie, or web-request
  permission and exposes no page-mutation command. A browser-side user gesture grants an optional origin;
  an inert picker is registered only there. During an explicit context request,
  the broker probes permitted active pages, binds the request to one exact tab
  and title-matched native-relay session, and accepts the clicked result only
  from those same endpoints through an extension-ID-allowlisted native host
  and a mode-0600 per-login Unix socket. It never streams tab changes or browsing
  history. The extension strips editable subtrees, their accessible-name and
  selection fallbacks, password values, hidden nodes,
  scripts, styles, event attributes, URL credentials, query strings, and
  fragments. The broker independently validates and caps the semantic tree,
  frames it as untrusted observational data, and exposes no browser action or
  arbitrary-script command.
- External links are allowlisted by scheme and are never passed through shell interpolation.
- The broker does not regex-classify prompts or implement action-specific
  shortcuts. Every ordinary question and action request follows the selected
  harness's same fixed policy and permission boundary.
- All providers receive the same hidden OmaPilot instructions. They treat
  desktop context as optional untrusted evidence, encourage discovery of
  relevant installed capabilities and current-information web search, prefer
  the system default browser for authorized navigation, and require tool
  evidence before claiming an action succeeded. These instructions complement
  the broker's structural fail-closed checks; they cannot enable a blocked tool,
  expand a sandbox, or turn natural-language output into a security boundary.
- Installed skill content is trusted provider instruction, not observational
  data. A skill can cause the harness to propose a command, but it cannot bypass
  the exact allow-once card or enable a denied tool. Review locally installed
  skills as part of the harness configuration.
- Desktop context comes only from Quickshell's public Hyprland and MPRIS
  objects. The active window is latched immediately before the panel takes
  focus; the remaining snapshot is captured at submit. It is limited to one active window, 12 deduplicated app
  records, 12 workspaces, and four playing-media records. Every string is
  length-bounded and rejects control and bidirectional-display characters at
  the broker boundary. Window
  titles and media metadata remain semantically untrusted, are framed as data
  rather than instructions, and never broaden a provider's tool authority.
  OmaPilot does not store the snapshot in its chat JSON, but the selected
  provider receives it as part of the native session prompt and may retain it.
  This framing cannot reduce Codex's existing host-read authority. Disable
  Desktop context in widget settings to omit the snapshot entirely.
- Permission prompts and raw tool input/output are ephemeral and are not copied
  to the completed chat record. The model's completed answer may contain
  tool-derived text and is retained normally. Provider stderr and raw tool
  output never cross the broker boundary.

The OmaPilot boundary ends when the user selects **Continue in Herdr**. Herdr
then owns the native harness session and its normal interactive permission
model. OmaPilot does not claim that a continued session remains tool-free.

This boundary reduces accidental authority; it is not an OS sandbox. A compromised plugin repository or verified runtime release would execute with the current user's permissions.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting for `spencerbull/omarchy-omapilot`. Do not open a public issue for an exploitable finding or include credentials, prompts, transcripts, or tokens in a report.

Include the OmaPilot version, Omarchy revision, provider, relevant logs with secrets removed, and a minimal reproduction. Receipt should be acknowledged within seven days; publication and remediation timing depend on severity and coordinated disclosure needs.
