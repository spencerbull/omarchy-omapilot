#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
installer="$repo_root/scripts/install-hotkeys.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/omapilot-hotkeys-test.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

export HOME="$test_root/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export OMAPILOT_HOTKEYS_NO_RELOAD=1
bindings="$XDG_CONFIG_HOME/hypr/bindings.lua"
mkdir -p -- "$(dirname -- "$bindings")"

assert_absent() {
  local needle="$1"
  local file="$2"
  if grep -Fq -- "$needle" "$file"; then
    printf 'unexpected text in %s: %s\n' "$file" "$needle" >&2
    exit 1
  fi
}

cat >"$bindings" <<'LUA'
-- Existing user configuration.
o.bind("SUPER + A", "My existing assistant", "my-assistant")
o.bind('SUPER + ALT + N', 'My existing new chat', 'my-new-chat')
LUA

if "$installer" --installed-plugin-only 2>/dev/null; then
  printf 'expected development-path installation to fail closed\n' >&2
  exit 1
fi
assert_absent '-- BEGIN OmaPilot managed hotkeys' "$bindings"

installed_dir="$HOME/.config/omarchy/plugins/io.github.spencerbull.omapilot"
installed_installer="$installed_dir/scripts/install-hotkeys.sh"
mkdir -p -- "$(dirname -- "$installed_installer")"
cp -- "$installer" "$installed_installer"
chmod 0755 "$installed_installer"

"$installed_installer" --installed-plugin-only
first_checksum=$(sha256sum "$bindings")
"$installed_installer" --installed-plugin-only
second_checksum=$(sha256sum "$bindings")
[[ $first_checksum == "$second_checksum" ]]

test "$(grep -Fc -- '-- BEGIN OmaPilot managed hotkeys' "$bindings")" -eq 1
test "$(grep -Fc -- 'o.bind("SUPER + A", "My existing assistant"' "$bindings")" -eq 1
assert_absent 'o.bind("SUPER + A", "Talk to OmaPilot"' "$bindings"
grep -Fq -- "o.bind('SUPER + ALT + N', 'My existing new chat'" "$bindings"
assert_absent 'o.bind("SUPER + ALT + N", "New OmaPilot chat"' "$bindings"
grep -Fq -- 'hl.unbind("SUPER + SHIFT + A")' "$bindings"
grep -Fq -- 'io.github.spencerbull.omapilot newVoiceChat' "$bindings"
grep -Fq -- 'hl.unbind("SUPER + ALT + A")' "$bindings"
grep -Fq -- 'io.github.spencerbull.omapilot captureVoice' "$bindings"
grep -Fq -- 'hl.unbind("SUPER + ALT + X")' "$bindings"
grep -Fq -- 'io.github.spencerbull.omapilot voiceCancel' "$bindings"
grep -Fq -- 'io.github.spencerbull.omapilot continueInHerdr' "$bindings"
"$installed_installer" --force
grep -Fq -- 'o.bind("SUPER + A", "Talk to OmaPilot"' "$bindings"
grep -Fq -- 'io.github.spencerbull.omapilot newChat' "$bindings"
test "$(grep -Fc -- '-- BEGIN OmaPilot managed hotkeys' "$bindings")" -eq 1

"$installed_installer" --remove
grep -Fq -- 'My existing assistant' "$bindings"
grep -Fq -- 'My existing new chat' "$bindings"
assert_absent '-- BEGIN OmaPilot managed hotkeys' "$bindings"

"$installed_installer"
assert_absent 'o.bind("SUPER + A", "Talk to OmaPilot"' "$bindings"
assert_absent 'o.bind("SUPER + ALT + N", "New OmaPilot chat"' "$bindings"
test "$(grep -Fc -- '-- BEGIN OmaPilot managed hotkeys' "$bindings")" -eq 1

"$installed_installer" --remove
clean_bindings="$test_root/clean-bindings.lua"
cp -- "$bindings" "$clean_bindings"

cat >>"$bindings" <<'LUA'
o.bind("SUPER + SHIFT + A", "My existing voice chat", "my-voice-chat")
o.bind("SUPER + ALT + A", "My existing capture voice", "my-capture-voice")
o.bind("SUPER + ALT + X", "My existing voice cancel", "my-voice-cancel")
o.bind("SUPER + ALT + H", "My existing handoff", "my-handoff")
LUA
all_collisions_checksum=$(sha256sum "$bindings")
if "$installed_installer" 2>/dev/null; then
  printf 'expected all-collisions installation to fail without completing setup\n' >&2
  exit 1
fi
test "$(sha256sum "$bindings")" = "$all_collisions_checksum"
assert_absent '-- BEGIN OmaPilot managed hotkeys' "$bindings"

cp -- "$clean_bindings" "$bindings"
cat >>"$bindings" <<'LUA'
-- BEGIN OmaPilot managed hotkeys
-- Legacy block from before the voice-cancel shortcut was added.
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "New OmaPilot voice chat",
  "omarchy-shell -q io.github.spencerbull.omapilot newVoiceChat")
hl.unbind("SUPER + ALT + H")
o.bind("SUPER + ALT + H", "Continue OmaPilot chat in Herdr",
  "omarchy-shell -q io.github.spencerbull.omapilot continueInHerdr")
-- END OmaPilot managed hotkeys
LUA
legacy_checksum=$(sha256sum "$bindings")
"$installed_installer"
test "$(grep -Fc -- '-- BEGIN OmaPilot managed hotkeys' "$bindings")" -eq 1
grep -Fq -- 'hl.unbind("SUPER + ALT + X")' "$bindings"
grep -Fq -- 'io.github.spencerbull.omapilot voiceCancel' "$bindings"
grep -Fq -- 'hl.unbind("SUPER + ALT + A")' "$bindings"
grep -Fq -- 'io.github.spencerbull.omapilot captureVoice' "$bindings"
test "$(sha256sum "$bindings")" != "$legacy_checksum"
upgraded_checksum=$(sha256sum "$bindings")
"$installed_installer"
test "$(sha256sum "$bindings")" = "$upgraded_checksum"

for mode in --remove --force; do
  cp -- "$clean_bindings" "$bindings"
  printf '%s\n' \
    '-- END OmaPilot managed hotkeys' \
    '-- user configuration between reversed markers' \
    '-- BEGIN OmaPilot managed hotkeys' \
    '-- user configuration after reversed markers' >>"$bindings"
  reversed_checksum=$(sha256sum "$bindings")
  if "$installed_installer" "$mode" 2>/dev/null; then
    printf 'expected reversed marker check to fail for %s\n' "$mode" >&2
    exit 1
  fi
  test "$(sha256sum "$bindings")" = "$reversed_checksum"
  grep -Fq -- '-- user configuration after reversed markers' "$bindings"
done

cp -- "$clean_bindings" "$bindings"
printf '%s\n' '-- BEGIN OmaPilot managed hotkeys' >>"$bindings"
unmatched_checksum=$(sha256sum "$bindings")
if "$installed_installer" 2>/dev/null; then
  printf 'expected malformed marker check to fail\n' >&2
  exit 1
fi
test "$(sha256sum "$bindings")" = "$unmatched_checksum"

printf 'Hotkey installer tests: ok\n'
