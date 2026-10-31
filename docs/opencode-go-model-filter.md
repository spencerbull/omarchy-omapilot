# OpenCode Go model filter

## Problem
OmaPilot's OpenCode picker listed every model from `opencode models` — 504 entries
on this machine (363 openrouter + 80 opencode + 30 opencode-go + 29 google +
locals). The 30 models paid for through the OpenCode Go subscription were buried.

Live count verified with `opencode models`:
- total: 504
- opencode-go/*: 30

## Change
When the provider is `opencode`, the broker now keeps only `opencode-go/*`
models, end to end. Codex and built-in providers are untouched.

- Display name is the short form (`kimi-k3`).
- Submitted value stays the full id (`opencode-go/kimi-k3`), so submits keep working.
- Filtering happens at three layers so no path leaks the full list:
  1. `runtime/src/providers.ts` — new `isOpenCodeGoModel`,
     `shortOpenCodeGoName`, `filterOpenCodeGoModels` helpers; `fallbackModels`
     (the `opencode models` CLI path) filters and shortens.
  2. `runtime/src/acp.ts` — live ACP probe and per-answer session models
     filtered for opencode only.
  3. `runtime/src/broker.ts` — both `provider.models` assignments (init +
     after each answer) filtered, belt-and-suspenders.
- `runtime/test/fixtures/bin/opencode` — `models` output now returns
  `opencode-go/fixture-default` plus a non-Go line (`other/thing`) so the
  filter is exercised. Verified the filter keeps exactly the Go entry with
  the short name `fixture-default`.

## Verification
- `tsc --noEmit`: clean.
- `vitest run runtime/test/policy.test.ts runtime/test/protocol.test.ts`:
  policy suite passes; protocol codex paths pass (18 passed). 4 opencode
  tool-permission tests time out — confirmed pre-existing by stashing these
  changes and re-running one on the clean tree (same timeout).
- `npm run build`: broker rebuilt, `runtime/dist/omapilot-broker` mtime/size
  updated, binary contains the `opencode-go` filter.
- `omarchy plugin validate .`: passes (after removing the `node_modules`
  build tree, which validation rejects for symlinks).
- Functional: fixture `models` output filters to 1 entry with short name;
  live `opencode models` yields 30 Go entries with correct short forms
  (e.g. `beam-free`, `claude-haiku-5-5`, `deepseek-v4-pro`).

## UI check
Open OmaPilot settings, harness = OpenCode. The Model dropdown should show
the 30 short names only, no `openrouter/`, `google/`, or bare `opencode/`
entries. Picking one submits the full `opencode-go/<name>` id.

## Files touched by this change
- runtime/src/providers.ts
- runtime/src/acp.ts
- runtime/src/broker.ts
- runtime/test/fixtures/bin/opencode
- runtime/dist/omapilot-broker (rebuilt)

Pre-existing local mods not part of this change (issue #42 pin work):
Panel.qml, components/OmaPilotStore.qml, manifest.json, package-lock.json,
runtime/test/policy.test.ts HOME/XDG isolation.
