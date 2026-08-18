#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
manifest="$repo_root/manifest.json"

fail() {
  printf 'check-manifest: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null || fail "jq is required"
jq -e . "$manifest" >/dev/null || fail "manifest.json is not valid JSON"

jq -e '
  .schemaVersion == 1
  and .id == "io.github.spencerbull.quickchat"
  and .name == "OmaPilot"
  and (.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+([.-][A-Za-z0-9.-]+)?$"))
  and .license == "MIT"
  and .kinds == ["bar-widget", "overlay"]
  and .keepLoaded == true
  and .entryPoints == {"barWidget":"BarWidget.qml", "overlay":"ContextCaptureOverlay.qml"}
  and .barWidget.category == "AI"
  and .barWidget.displayName == "OmaPilot"
  and (.barWidget.aliases | index("omapilot") != null)
  and (.barWidget.aliases | index("quickchat") != null)
  and .barWidget.allowMultiple == false
  and .barWidget.defaultSection == "right"
  and .barWidget.defaults == {
    "provider":"builtin",
    "builtinModel":"",
    "codexModel":"",
    "claudeModel":"",
    "opencodeModel":"",
    "quickActionsJson":"",
    "desktopContext":"On",
    "dangerousAutoApprove":false
  }
  and ([.barWidget.schema[].key] | sort) == (["builtinModel", "claudeModel", "codexModel", "dangerousAutoApprove", "desktopContext", "opencodeModel", "provider"] | sort)
  and (.barWidget.schema[] | select(.key == "dangerousAutoApprove")) == {
    "key":"dangerousAutoApprove",
    "type":"boolean",
    "label":"Dangerous auto-approve",
    "defaultValue":false,
    "description":"Automatically select each exact tool request\u0027s Allow once option instead of prompting."
  }
' "$manifest" >/dev/null || fail "manifest contract drifted from the Quickchat v0.1 schema"

[[ -f "$repo_root/BarWidget.qml" ]] || fail "manifest entry point is missing: BarWidget.qml"
[[ -f "$repo_root/ContextCaptureOverlay.qml" ]] || fail "manifest entry point is missing: ContextCaptureOverlay.qml"

while IFS= read -r path; do
  [[ $path != /* && $path != *..* ]] || fail "unsafe manifest entry point: $path"
  [[ -f "$repo_root/$path" ]] || fail "missing manifest entry point: $path"
done < <(jq -r '.entryPoints[]' "$manifest")

if find "$repo_root" \
  \( -path "$repo_root/.git" -o -path "$repo_root/node_modules" -o -path "$repo_root/dist" \) -prune \
  -o -type l -print -quit | grep -q .; then
  fail "repository contains a symlink; Omarchy refuses plugin folders containing symlinks"
fi

printf 'Manifest contract: ok\n'
