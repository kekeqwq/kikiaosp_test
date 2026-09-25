#!/usr/bin/env bash
set -euo pipefail
AOSP_ROOT=${1:-$PWD}
REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ -d "$AOSP_ROOT/.repo" ] || { echo "not an AOSP checkout: $AOSP_ROOT" >&2; exit 2; }
"$REPO_ROOT/scripts/sync-device-tree.sh" "$AOSP_ROOT"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-working-tree.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-kikiaosp-no-sensor-rotation.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-kikiaosp-no-sensor-wake-gesture.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-device-state-lazy-sensors.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-selinux-runtime-diagnostic.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-selinux-avc-decision-diagnostic.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-selinux-avc-error-diagnostic.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-selinux-avc-stage-diagnostic.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-selinux-avc-stage-completion.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-selinux-avc-mount-type-diagnostic.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-selinux-mount-namespace-diagnostic.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-selinux-init-thread-view-diagnostic.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-kikiaosp-single-mount-namespace.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-render-output.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-sf-layerhandle-diagnostics.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-hwc-guest-composer.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-hwc-device-buffer-map.patch"
while IFS= read -r -d '' src; do
  rel=${src#"$REPO_ROOT/overlays/"}
  mkdir -p "$AOSP_ROOT/$(dirname "$rel")"
  cp -f "$src" "$AOSP_ROOT/$rel"
done < <(find "$REPO_ROOT/overlays" -type f -print0)
echo "KikiAOSP device tree and integration patches applied to $AOSP_ROOT"
