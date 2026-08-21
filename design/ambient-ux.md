# OmaPilot ambient UX — replacing the bar widget

Status: design accepted in principle (owner, 2026-08-19), not implemented.
Branch `voice-node-design`. The runnable concept is `design/voice-node-mock.qml`.

## The decision

OmaPilot stops being a bar widget with a popout panel and becomes an
**ambient desktop surface**. The bar icon, the anchored panel, and the
`bar-widget` kind all go away. Voice is the primary input; the desktop edges are
the primary output.

This is not a reskin. The panel is currently the only place any capability
lives, so removing it forces every capability to be re-homed. That remap is the
substance of this document.

## Three surfaces

| Surface | Edge | Focus | Input region | Purpose |
| --- | --- | --- | --- | --- |
| **Node** | bottom | never | none (`mask: Region {}`) | Voice presence and live transcript. Light, not a widget. |
| **Curtain** | top, under the bar | none, grabbable | none until grabbed | The answer. Glance, then gone. |
| **Console** | centred | exclusive while open | full | The deliberate lane: typing, choices, settings, history, permissions, auth. |

The node and the curtain are **ambient**: they never take a click or a
keystroke, so they cannot interrupt what the user is doing. The console is the
only surface that takes focus, and only on explicit summon or when a decision
genuinely blocks progress.

Why a third surface at all: permissions, built-in authentication, settings,
history, and attachment-representation choices all require real focus and real
interaction. Pushing them into an edge glow would be bad design, and for
permission decisions it would be unsafe. Ambient for the common path; one
honest console for everything else.

## Capability remap

Every capability the panel and bar widget own today, and where it goes.

| Capability | Today | New home |
| --- | --- | --- |
| Bar icon, busy state, tooltip | `BarIconButton` + `OmaPilotMark` | **Removed.** The node's presence *is* the state. |
| Open / close / toggle | bar click, IPC | Hotkeys → IPC. Hold to talk, tap for console. |
| Text composer | `Composer.qml` in panel | Console, typed lane |
| Provider / model selection | Composer dropdowns | Console → settings |
| Submit | Composer send button | Voice release, or console Enter |
| Streaming answer | panel response card | Curtain |
| Markdown, images, links | `MarkdownView` in panel | Curtain (grab to scroll, copy, open) |
| Response activity runner | response card perimeter | Node filament runner (ported) |
| Quick actions | panel chips | Console, keyboard-first list |
| History (latest 30) | `HistoryView` in panel | Console → history lane |
| Settings | `SettingsView.qml` | Console → settings lane (now the only settings authority) |
| Permission allow-once / reject-once | panel inline | **Console, force-summoned.** Safety-critical; must be focused and explicit. |
| Built-in auth (prompt, device code, browser) | panel | **Console, force-summoned.** Needs typed input. |
| Errors and error details | `ErrorNotice`, `ErrorDetailsView` | Node turns urgent; summary in curtain; full detail in console |
| Context capture overlay | `ContextCaptureOverlay.qml` | **Unchanged.** Already an overlay surface. |
| Attachment representation choice | `ContextAttachmentPreview` in panel | Console — it is a choice, so it needs focus |
| Dictation start / stop / cancel | mic button in composer | Node. This is now the primary gesture. |
| Continue in Herdr | panel button | Console action |
| Copy answer | panel button | Curtain hotkey while grabbed |
| Desktop context on/off | `manifest.barWidget.schema` | Console → settings |
| Dangerous auto-approve | `manifest.barWidget.schema` | Console → settings |
| Browser companion install / remove | `SettingsView` | Console → settings (unchanged behaviour) |

Nothing in the broker changes. The runtime command/event contract, the provider
policies, the permission nonce boundary, and history all stay exactly as they
are. This is a presentation-layer remap, which is why it is worth doing at all.

## Host contract change

Dropping `bar-widget` changes how Omarchy discovers, enables, and persists the
plugin. This was verified against the installed shell (Omarchy `4.0.0.alpha`,
Quickshell `0.3.0`, Hyprland `0.56.2`) rather than assumed.

**It works with no host changes.** For a third-party plugin whose `kinds` omit
`bar-widget`:

- `omarchy plugin enable <id>` → `omarchy-shell shell enablePlugin` →
  `PluginRegistry.setEnabled`, which reaches
  `else if (!location.found && !isFirstParty) config.plugins.push(entry)`.
  The entry lands in `shell.json` `plugins[]` instead of `bar.layout.center[]`.
- `PluginRegistry.isEnabled` → `findEntryLocation`, which searches `plugins[]`.
- `shell.updateEntryInline(id, entry)` already has a `plugins[]` branch, so
  **inline settings persistence keeps working unchanged**.
- `manifest.keepLoaded: true` keeps the overlay Loader active from shell start,
  so the node exists before the first summon.
- `omarchy plugin disable <id>` removes the `plugins[]` entry.

**The one real gap.** `shell.qml`'s panel/overlay Loader injects `omarchyPath`,
`shell`, `manifest`, `barWidgetRegistry`, `pluginRegistry`, and `service` — but
**not `settings`**. Only the bar-widget registry path injects `settings`. So the
overlay must read its own entry out of `shell.shellConfig.plugins[]` and keep
writing through `shell.updateEntryInline`. That is one small adapter, and it is
the only new plumbing the host change requires.

**Two consequences worth accepting deliberately:**

1. `manifest.barWidget.schema` and `defaults` stop being read. Omarchy's
   bar-settings form no longer renders our preferences, and the host no longer
   supplies defaults. Defaults move into our code and the console owns the form.
   This matches the goal of putting configuration in settings.
2. Enablement loses its GUI affordance. Bar widgets are discoverable because
   users add them to the bar; an overlay-only plugin is enabled from the CLI
   (`omarchy plugin enable io.github.spencerbull.omapilot`) or by hand-editing
   `shell.json`. The README must lead with that command. Every one of the 11
   plugins currently installed on this machine declares `bar-widget`, so
   overlay-only is an untrodden path in Quattro — expect to be the first to
   find its rough edges.

## Focus and input model

The rule that makes this feel like the OS instead of an app: **voice must never
move keyboard focus.** If talking to OmaPilot steals focus from the editor the
user is typing in, the illusion dies immediately.

- Node — `WlrKeyboardFocus.None`, `mask: Region {}`, `ExclusionMode.Ignore`.
  Permanently inert. Feedback only.
- Curtain — `keyboardFocus: None` and click-through by default, so an answer can
  appear while the user keeps typing. A hotkey *grabs* it, switching it to
  focused and interactive for scrolling, copying, and opening links.
  `ExclusionMode.Normal` with `exclusiveZone: 0`, so it respects the bar's
  reserved strip and reserves nothing itself — no window ever reflows.
- Console — `WlrKeyboardFocus.Exclusive` while open, `ExclusionMode.Ignore`.
  The only focus thief, and only when asked.

Because voice never focuses, the trigger cannot be a surface keybinding; it has
to be a compositor binding that routes over IPC.

## Hotkeys

Hyprland 0.56's Lua `hl.bind` accepts `release` and `long_press` options, which
lets one key carry both gestures:

```lua
-- Hold to talk; the node lights while held and submits on release.
o.bind("SUPER + SPACE", "Talk to OmaPilot",
  "omarchy-shell -q io.github.spencerbull.omapilot voiceStart",
  { long_press = true })
o.bind("SUPER + SPACE", "Finish talking",
  "omarchy-shell -q io.github.spencerbull.omapilot voiceStop",
  { release = true })

-- Tap the same key for the typed console.
o.bind("SUPER + SPACE", "OmaPilot console",
  "omarchy-shell -q shell toggle io.github.spencerbull.omapilot")
```

These are **documented user bindings, not something OmaPilot writes**. The
plugin does not edit Hyprland configuration; that constraint is unchanged.

Layer rules are likewise optional and user-owned. Real backdrop blur behind the
ambient surfaces needs
`hl.layer_rule({ match = { namespace = "omapilot-node" }, blur = true })`, and
`decoration:blur:enabled` is currently `false` on this machine. The design
therefore earns its legibility from pixels it draws itself and treats blur as a
bonus, never a requirement.

## Visual language

One light source, one accent, no second palette.

- **Ember** — a full-width transparent gradient sunk below the bottom edge so
  only its bloom reaches the desktop. Its low-energy corners keep the complete
  lower edge alive without drawing a visible bar. Two slow, incommensurate
  cycles shift its breath and center slightly; neither represents microphone
  amplitude. Two stacked blooms keep atmosphere and definition separate.
- **Filament** — a hairline at the very edge that makes the glow read as
  deliberate rather than as a rendering artifact.
- **Runner** — while thinking, one short bright segment sweeps the filament.
  Same vocabulary as the existing response perimeter runner, flattened to a
  line, so the surfaces feel like one product.
- **Plate** — the caption backing. Two stacked feathered passes sized to the
  text, kept translucent. Density accumulates at the centre faster than a rim
  accumulates at the edge, so it is legible over a white browser and
  effectively invisible over a dark terminal. Containment appears only where it
  is needed, with no theme branch or mode switch.

Motion is ours, not the compositor's: Omarchy pins `layersIn`/`layersOut` to a
global fade, so the curtain animates its own `y` (OutQuint, 300 ms in / 220 ms
out) inside a static surface.

**Honesty constraint.** The node breathes on a fixed rhythm and does not
pretend to show audio amplitude. The broker emits `recording`, `transcribing`,
`idle`, and `unavailable` with no level data, so a VU meter would be a lie in
pixels.

## Staging

1. Overlay root that owns node + curtain + existing context capture, plus the
   settings adapter that reads `shell.shellConfig.plugins[]`.
2. Console with the typed lane, permissions, and built-in auth — the blocking
   paths — before anything cosmetic.
3. Migrate settings, history, and quick actions into the console.
4. Drop `bar-widget` from the manifest, delete `BarWidget.qml` and `Panel.qml`,
   rewrite enablement docs.
5. Reduced-motion and single-surface fallbacks; multi-monitor placement rules.

Step 4 is the irreversible one and must come last: until the console covers
permissions and auth, the panel is still the only way to approve a device
command, and removing it early would strand the user mid-flow.

## Placement: the focused output

All three surfaces follow the output Hyprland has focused, so the light appears
on the screen the user is actually working on rather than on a fixed display.
The resolution reuses the shell's own canonical pattern from
`plugins/bar/Bar.qml`:

```qml
readonly property string focusedScreenName:
  Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
```

Hyprland reports no focused monitor briefly at startup, so the binding falls
back to the first screen rather than rendering nowhere — the same caveat the bar
documents. Verified on this two-output setup (`eDP-1` + `DP-1`):
`hyprland=eDP-1 resolved=eDP-1`.

Because `screen` is a live binding, moving focus between displays migrates the
surfaces with it. State lives on the root, so a phase in progress survives the
migration.

## Dismissal: scaled, not fixed

The curtain auto-dismisses. The delay scales with how much there is to read
rather than being a flat timeout, because a fixed 8 s eats a long answer
mid-sentence:

```
max(6000, min(40000, 4500 + words * 240))   // ms
```

Roughly 240 ms per word over a floor, clamped so a one-liner still lingers and
an essay cannot camp on the desktop. Measured: a one-word answer unmaps at 6 s;
a 31-word answer computes 11 940 ms.

The timer only runs once the answer has settled, so streaming never races it,
and it restarts when new content arrives.

**Accepted cost.** Production should also hold the timer while the curtain is
grabbed, but it cannot pause on hover: the node and curtain are click-through
(`mask: Region {}`), so they receive no pointer events at all. Giving the
curtain an input region would buy hover-to-pause at the price of intercepting
clicks in a strip across the top of the screen. Never intercepting a click is
worth more than hover-to-pause, so the grab hotkey is the escape hatch.

When dormant, every OmaPilot surface unmaps — the plugin leaves nothing on the
output while idle.

## Findings from the local install

Three things only a real install surfaced.

**1. Voxtype already owns the bottom centre.** `/usr/lib/voxtype/voxtype-osd-gtk4`
is a separate GTK4 process that draws a waveform card at the bottom centre of the
focused output while recording — exactly where the node lives. Two indicators for
one state is worse than either alone. This needs an owner decision: suppress the
Voxtype OSD and let the node be the sole indicator, or keep the OSD and drop the
node's listening state. Nothing in the plugin should silently disable a
user-configured tool, so the plugin does not touch it.

**2. Amplitude really is unavailable, confirmed rather than assumed.**
`voxtype status --follow --extended --format json` exists and is already consumed
by `herdr-bridge`, so it looked like a level source. It is not: the payload is
Waybar-shaped — `text`, `alt`, `class`, `tooltip`, `model`, `device`, `backend`
— with no amplitude field. Voxtype's own OSD reads the audio device directly. The
node's fixed-rhythm breath stands as the honest choice; a real waveform would
need the broker to tap audio or Voxtype to expose levels, and neither exists.

**3. Dismissal had to release the microphone.** The first live run left Voxtype
recording after `dismiss()` — a hot mic with no indicator on screen, which is the
one failure mode an invisible ambient layer must never have. `dismiss()` now
cancels in-flight dictation. Verified live: Voxtype goes `recording` → `idle`.

## Open questions

- Should the console be summonable to a chosen edge, or always centred?
- Are answers **spoken**? Nothing in the broker does TTS today. If voice output
  is part of "voice node", the curtain becomes a transcript rather than the
  primary channel, and dismissal should follow speech end instead of a word
  count.
- Is the built-in Pi harness the default provider for the voice path?
