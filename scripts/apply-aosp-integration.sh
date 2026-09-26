#!/usr/bin/env bash
set -euo pipefail
AOSP_ROOT=${1:-$PWD}
REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ -d "$AOSP_ROOT/.repo" ] || { echo "not an AOSP checkout: $AOSP_ROOT" >&2; exit 2; }
"$REPO_ROOT/scripts/sync-device-tree.sh" "$AOSP_ROOT"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-working-tree.patch"
while IFS= read -r -d '' src; do
  rel=${src#"$REPO_ROOT/overlays/"}
  mkdir -p "$AOSP_ROOT/$(dirname "$rel")"
  cp -f "$src" "$AOSP_ROOT/$rel"
done < <(find "$REPO_ROOT/overlays" -type f -print0)
echo "KikiAOSP device tree and integration patches applied to $AOSP_ROOT"
