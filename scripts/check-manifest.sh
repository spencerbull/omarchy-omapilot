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
  and .id == "io.github.spencerbull.omapilot"
  and .name == "OmaPilot"
  and (.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+([.-][A-Za-z0-9.-]+)?$"))
  and .license == "MIT"
  and .kinds == ["bar-widget", "overlay"]
  and .keepLoaded == true
  and .entryPoints == {"barWidget":"BarWidget.qml", "overlay":"Ambient.qml"}
  and .barWidget.category == "AI"
  and .barWidget.displayName == "OmaPilot"
  and (.barWidget.aliases | index("omapilot") != null)
  and .barWidget.allowMultiple == false
  and .barWidget.defaultSection == "right"
  and .barWidget.defaults == {
    "provider":"builtin",
    "builtinModel":"",
    "codexModel":"",
    "opencodeModel":"",
    "quickActionsJson":"",
    "desktopContext":"On",
    "webHandoffProvider":"duckduckgo",
    "dangerousAutoApprove":false,
    "voiceEnabled":false,
    "voiceVisualizer":"segments",
    "thinkingVisualizer":"bumper",
    "ttsProvider":"elevenlabs",
    "ttsModel":"",
    "ttsVoice":"",
    "onboardingComplete":false
  }
  and ([.barWidget.schema[].key] | sort) == (["builtinModel", "codexModel", "dangerousAutoApprove", "desktopContext", "opencodeModel", "provider", "thinkingVisualizer", "ttsModel", "ttsProvider", "ttsVoice", "voiceEnabled", "voiceVisualizer", "webHandoffProvider"] | sort)
  and (.barWidget.schema[] | select(.key == "webHandoffProvider")) == {
    "key":"webHandoffProvider",
    "type":"enum",
    "label":"Search provider",
    "options":["duckduckgo", "google", "chatgpt", "claude", "grok"],
    "defaultValue":"duckduckgo",
    "description":"Choose where OmaPilot opens current-information questions. AI sites also receive a paste-ready copy; answers stay in the browser."
  }
  and (.barWidget.schema[] | select(.key == "dangerousAutoApprove")) == {
    "key":"dangerousAutoApprove",
    "type":"boolean",
    "label":"Dangerous auto-approve",
    "defaultValue":false,
    "description":"Automatically select each exact tool request\u0027s Allow once option instead of prompting."
  }
  and (.barWidget.schema[] | select(.key == "voiceEnabled")) == {
    "key":"voiceEnabled",
    "type":"boolean",
    "label":"Enable voice",
    "defaultValue":false,
    "description":"Allow talking to OmaPilot and speaking answers after a TTS provider is ready."
  }
  and (.barWidget.schema[] | select(.key == "voiceVisualizer")) == {
    "key":"voiceVisualizer",
    "type":"enum",
    "label":"Listening visualizer",
    "options":["segments", "spectrum", "dots", "line"],
    "defaultValue":"segments",
    "description":"Choose the visualizer shown while you speak."
  }
  and (.barWidget.schema[] | select(.key == "thinkingVisualizer")) == {
    "key":"thinkingVisualizer",
    "type":"enum",
    "label":"Thinking visualizer",
    "options":["scanner", "bumper"],
    "defaultValue":"bumper",
    "description":"Choose the visualizer shown after dictation while OmaPilot prepares the answer."
  }
  and (.barWidget.schema[] | select(.key == "ttsProvider")) == {
    "key":"ttsProvider",
    "type":"enum",
    "label":"TTS provider",
    "options":["elevenlabs", "kokoro", "openai"],
    "defaultValue":"elevenlabs",
    "description":"ElevenLabs is the guided default. Kokoro is local; ElevenLabs and OpenAI keys are stored in voice-auth.json."
  }
' "$manifest" >/dev/null || fail "OmaPilot manifest contract drifted"

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
