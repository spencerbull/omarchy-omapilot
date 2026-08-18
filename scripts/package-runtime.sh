#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
output_dir="$repo_root/dist/release"
dry_run=0
platform="linux-x86_64"

usage() {
  cat <<'USAGE'
Usage: scripts/package-runtime.sh [--dry-run] [--output-dir DIR]

Assemble (but do not publish) the pinned Quickchat ACP runtime for Linux x86-64.
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      output_dir=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'package-runtime: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

required=(
  package.json
  package-lock.json
  runtime/dist/quickchat-broker.js
  runtime/dist/quickchat-broker.js.LEGAL.txt
  runtime/dist/adapters/codex-acp.js
  runtime/dist/adapters/claude-agent-acp.js
  runtime/dist/adapters/claude-agent-acp.js.LEGAL.txt
  runtime/dist/adapters/Apache-2.0.txt
  runtime/policies/automatic.md
  runtime/bin/quickchat-broker
  runtime/bin/codex-acp
  runtime/bin/claude-agent-acp
  runtime/adapters.release.json
  runtime/policies/automatic.md
  THIRD_PARTY_NOTICES.md
  LICENSE
)

if ((dry_run)); then
  printf 'Runtime packaging dry run\n'
  printf '  platform: %s\n' "$platform"
  printf '  output:   %s\n' "$output_dir"
  printf '  inputs:\n'
  for relative in "${required[@]}"; do
    if [[ -e "$repo_root/$relative" ]]; then
      printf '    present  %s\n' "$relative"
    else
      printf '    pending  %s\n' "$relative"
    fi
  done
  printf '  actions: lockfile SBOM; normalized tar; SHA-256\n'
  exit 0
fi

for relative in "${required[@]}"; do
  [[ -f "$repo_root/$relative" ]] || {
    printf 'package-runtime: missing required input: %s\n' "$relative" >&2
    exit 1
  }
done

command -v npm >/dev/null || { printf 'package-runtime: npm is required\n' >&2; exit 1; }
command -v jq >/dev/null || { printf 'package-runtime: jq is required\n' >&2; exit 1; }
command -v tar >/dev/null || { printf 'package-runtime: tar is required\n' >&2; exit 1; }
command -v gzip >/dev/null || { printf 'package-runtime: gzip is required\n' >&2; exit 1; }
command -v sha256sum >/dev/null || { printf 'package-runtime: sha256sum is required\n' >&2; exit 1; }

[[ $(uname -s) == Linux && $(uname -m) =~ ^(x86_64|amd64)$ ]] || {
  printf 'package-runtime: linux-x86_64 packaging requires an x86-64 Linux builder\n' >&2
  exit 1
}
node_major=$(node --version | sed -E 's/^v([0-9]+).*/\1/')
[[ $node_major =~ ^[0-9]+$ && $node_major -ge 22 ]] || {
  printf 'package-runtime: Node.js 22 or newer is required\n' >&2
  exit 1
}

version=$(jq -r '.version' "$repo_root/manifest.json")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] || {
  printf 'package-runtime: invalid manifest version: %s\n' "$version" >&2
  exit 1
}

stage_parent=$(mktemp -d "${TMPDIR:-/tmp}/quickchat-package.XXXXXX")
trap 'rm -rf -- "$stage_parent"' EXIT
bundle_name="omarchy-quickchat-runtime-${version}-${platform}"
stage="$stage_parent/$bundle_name"
mkdir -p "$stage/runtime/dist/adapters" "$stage/runtime/bin" "$stage/runtime/policies"

cp "$repo_root/package.json" "$repo_root/package-lock.json" "$stage/"
cp "$repo_root/runtime/dist/quickchat-broker.js" "$stage/runtime/dist/"
cp "$repo_root/runtime/dist/quickchat-broker.js.LEGAL.txt" "$stage/runtime/dist/"
cp "$repo_root/runtime/dist/adapters/codex-acp.js" "$stage/runtime/dist/adapters/"
cp "$repo_root/runtime/dist/adapters/claude-agent-acp.js" "$stage/runtime/dist/adapters/"
cp "$repo_root/runtime/dist/adapters/claude-agent-acp.js.LEGAL.txt" "$stage/runtime/dist/adapters/"
cp "$repo_root/runtime/dist/adapters/Apache-2.0.txt" "$stage/runtime/dist/adapters/"
cp "$repo_root/runtime/policies/automatic.md" "$stage/runtime/policies/"
cp "$repo_root/runtime/bin/quickchat-broker" "$repo_root/runtime/bin/codex-acp" \
  "$repo_root/runtime/bin/claude-agent-acp" "$stage/runtime/bin/"
cp "$repo_root/runtime/adapters.release.json" "$stage/runtime/"
cp "$repo_root/runtime/policies/automatic.md" "$stage/runtime/policies/"
cp "$repo_root/THIRD_PARTY_NOTICES.md" "$repo_root/LICENSE" "$stage/"
chmod 0755 "$stage/runtime/bin/quickchat-broker" "$stage/runtime/bin/codex-acp" \
  "$stage/runtime/bin/claude-agent-acp"

(
  cd "$stage"
  # The three executables are already self-contained bundles. The lockfile is
  # retained for exact source provenance and SBOM generation; including a
  # second node_modules copy would add hundreds of megabytes without changing
  # runtime behavior.
  npm sbom --package-lock-only --omit=dev --sbom-format cyclonedx \
    | jq 'del(.serialNumber, .metadata.timestamp)' > sbom.cdx.json
)

commit=$(git -C "$repo_root" rev-parse HEAD)
node_version=$(node --version)
jq -n \
  --arg version "$version" \
  --arg platform "$platform" \
  --arg commit "$commit" \
  --arg node "$node_version" \
  '{schemaVersion:1, pluginVersion:$version, platform:$platform, gitCommit:$commit, nodeVersion:$node, buildCommand:"scripts/package-runtime.sh", sourceDateEpoch:1}' \
  > "$stage/provenance.json"

find "$stage" -exec touch -h -d '@1' {} +
mkdir -p "$output_dir"
archive="$output_dir/$bundle_name.tar.gz"
tar --sort=name --mtime='@1' --owner=0 --group=0 --numeric-owner \
  -C "$stage_parent" -cf - "$bundle_name" | gzip -n > "$archive"

(
  cd "$output_dir"
  sha256sum "$(basename -- "$archive")" > SHA256SUMS
  cp "$stage/sbom.cdx.json" "$bundle_name.sbom.cdx.json"
  cp "$stage/provenance.json" "$bundle_name.provenance.json"
)

printf 'Created %s\n' "$archive"
printf 'Checksums: %s/SHA256SUMS\n' "$output_dir"
