#!/usr/bin/env bash
# Install Snapkey from a checkout, or from a single curl line:
#   curl -fsSL https://raw.githubusercontent.com/RobbieUK1/snapkey/main/install.sh | bash
set -euo pipefail

repo="${SNAPKEY_REPO:-RobbieUK1/snapkey}"
ref="${SNAPKEY_REF:-main}"

# A checkout already has everything: use its installer directly.
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || pwd)
if [[ -f $here/plugin/manifest.json && -x $here/bin/install ]]; then
  exec "$here/bin/install"
fi

for tool in curl tar; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "install: $tool is required" >&2
    exit 1
  }
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/snapkey.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Snapkey ($repo@$ref)…"
curl --fail --silent --show-error --location \
  "https://github.com/$repo/archive/refs/heads/$ref.tar.gz" |
  tar -xz -C "$tmp" --strip-components=1

"$tmp/bin/install"
