#!/usr/bin/env bash
set -euo pipefail

plugin_id="io.github.spencerbull.omapilot"
begin_marker="-- BEGIN OmaPilot managed hotkeys"
end_marker="-- END OmaPilot managed hotkeys"

installed_plugin_only=0
force=0
remove=0

usage() {
  cat <<'USAGE'
Usage: scripts/install-hotkeys.sh [--installed-plugin-only] [--force|--remove]

Install OmaPilot's global bindings into the user's Hyprland bindings.lua.

  --installed-plugin-only  Require OmaPilot's normal installed path.
  --force                  Replace colliding user bindings for OmaPilot's chords.
  --remove                 Remove only the block managed by this script.
USAGE
}

fail() {
  printf 'install-hotkeys: %s\n' "$*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --installed-plugin-only)
      installed_plugin_only=1
      ;;
    --force)
      force=1
      ;;
    --remove)
      remove=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown option: $1"
      ;;
  esac
  shift
done

(( !(force && remove) )) || fail "--force and --remove cannot be used together"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -L)
plugin_dir=$(cd -- "$script_dir/.." && pwd -L)

if ((installed_plugin_only)); then
  expected_plugin_dir="${HOME:?HOME is required}/.config/omarchy/plugins/$plugin_id"
  [[ $plugin_dir == "$expected_plugin_dir" ]] ||
    fail "refusing to edit bindings outside the installed plugin: $expected_plugin_dir"
fi

config_home="${XDG_CONFIG_HOME:-${HOME:?HOME is required}/.config}"
bindings_file="${OMAPILOT_HOTKEYS_BINDINGS_FILE:-$config_home/hypr/bindings.lua}"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}"
state_dir="${OMAPILOT_HOTKEYS_STATE_DIR:-$state_root/omapilot}"
lock_file="$state_dir/hotkeys.lock"

mkdir -p -- "$state_dir"
command -v flock >/dev/null || fail "flock is required"
exec 9>"$lock_file"
flock 9

[[ -f $bindings_file ]] || fail "Hyprland bindings file not found: $bindings_file"

reload_hyprland() {
  [[ ${OMAPILOT_HOTKEYS_NO_RELOAD:-0} != 1 ]] || return 0
  command -v hyprctl >/dev/null || return 0
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return 0

  hyprctl reload >/dev/null || fail "Hyprland reload failed"
  local errors
  errors=$(hyprctl configerrors)
  if [[ -n ${errors//[[:space:]]/} ]]; then
    printf 'install-hotkeys: Hyprland reported configuration errors:\n%s\n' "$errors" >&2
    return 1
  fi
}

marker_count() {
  local marker="$1"
  grep -Fxc -- "$marker" "$bindings_file" || true
}

begin_count=$(marker_count "$begin_marker")
end_count=$(marker_count "$end_marker")
(( begin_count <= 1 && end_count <= 1 && begin_count == end_count )) ||
  fail "refusing to edit malformed OmaPilot markers in $bindings_file"
if ((begin_count == 1)); then
  read -r begin_line end_line < <(
    awk -v begin="$begin_marker" -v end="$end_marker" '
      $0 == begin { begin_line = NR }
      $0 == end { end_line = NR }
      END { print begin_line, end_line }
    ' "$bindings_file"
  )
  ((begin_line < end_line)) ||
    fail "refusing to edit reversed OmaPilot markers in $bindings_file"
fi

remove_managed_block() {
  local temporary
  temporary=$(mktemp "$state_dir/bindings.XXXXXX")
  awk -v begin="$begin_marker" -v end="$end_marker" '
    $0 == begin { managed = 1; next }
    $0 == end { managed = 0; next }
    !managed { print }
  ' "$bindings_file" >"$temporary"
  cat "$temporary" >"$bindings_file"
  rm -f -- "$temporary"
}

if ((remove)); then
  if ((begin_count == 1)); then
    remove_managed_block
    reload_hyprland
  fi
  exit 0
fi

update_existing=0
if ((begin_count == 1)); then
  if ((force)); then
    remove_managed_block
  else
    update_existing=1
  fi
fi

has_user_binding() {
  local chord="$1"
  awk -v chord="$chord" '
    /^[[:space:]]*(o\.bind|hl\.bind|hl\.unbind)[[:space:]]*\(/ &&
      (index($0, "\"" chord "\"") ||
       index($0, sprintf("%c%s%c", 39, chord, 39))) { found = 1; exit }
    END { exit !found }
  ' "$bindings_file"
}

chords=(
  "SUPER + A"
  "SUPER + ALT + A"
  "SUPER + SHIFT + A"
  "SUPER + ALT + X"
  "SUPER + ALT + N"
  "SUPER + ALT + H"
)
descriptions=(
  "Talk to OmaPilot"
  "Capture screen and talk to OmaPilot"
  "New OmaPilot voice chat"
  "Cancel OmaPilot voice mode"
  "New OmaPilot chat"
  "Continue OmaPilot chat in Herdr"
)
commands=(
  "omarchy-shell -q io.github.spencerbull.omapilot voiceToggle"
  "omarchy-shell -q io.github.spencerbull.omapilot captureVoice"
  "omarchy-shell -q io.github.spencerbull.omapilot newVoiceChat"
  "omarchy-shell -q io.github.spencerbull.omapilot voiceCancel"
  "omarchy-shell -q io.github.spencerbull.omapilot newChat"
  "omarchy-shell -q io.github.spencerbull.omapilot continueInHerdr"
)

block_file=$(mktemp "$state_dir/hotkeys.XXXXXX")
candidate_file=$(mktemp "$state_dir/bindings-candidate.XXXXXX")
trap 'rm -f -- "${block_file:-}" "${candidate_file:-}"' EXIT

installed_count=0
{
  if ((!update_existing)); then
    printf '%s\n' "$begin_marker"
    printf '%s\n' '-- Added at the user request from OmaPilot settings. Edit these bindings freely.'
  fi
  for index in "${!chords[@]}"; do
    if ((!force)) && has_user_binding "${chords[$index]}"; then
      printf 'install-hotkeys: leaving existing %s binding unchanged\n' \
        "${chords[$index]}" >&2
      continue
    fi

    printf 'hl.unbind("%s")\n' "${chords[$index]}"
    printf 'o.bind("%s", "%s",\n  "%s")\n' \
      "${chords[$index]}" "${descriptions[$index]}" "${commands[$index]}"
    installed_count=$((installed_count + 1))
  done
  if ((!update_existing)); then
    printf '%s\n' "$end_marker"
  fi
} >"$block_file"

if ((installed_count == 0)); then
  if ((update_existing)); then
    reload_hyprland
    exit 0
  fi
  fail "no global hotkeys were installed because all shortcut chords are already in use"
fi

if ((update_existing)); then
  awk -v end="$end_marker" -v additions="$block_file" '
    $0 == end {
      while ((getline line < additions) > 0) print line
      close(additions)
    }
    { print }
  ' "$bindings_file" >"$candidate_file"
else
  {
    cat "$bindings_file"
    printf '\n'
    cat "$block_file"
  } >"$candidate_file"
fi

if command -v luac >/dev/null; then
  luac -p "$candidate_file" || fail "generated bindings are not valid Lua"
fi

cat "$candidate_file" >"$bindings_file"
reload_hyprland
