#!/usr/bin/env bash
set -euo pipefail
AOSP_ROOT=${1:-$PWD}
REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ -d "$AOSP_ROOT/.repo" ] || { echo "not an AOSP checkout: $AOSP_ROOT" >&2; exit 2; }
"$REPO_ROOT/scripts/sync-device-tree.sh" "$AOSP_ROOT"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-working-tree.patch"
patch -d "$AOSP_ROOT" -p1 --forward < "$REPO_ROOT/patches/aosp-kikiaosp-retain-gallery2.patch"
camera_sources_patch="$REPO_ROOT/device/kiki/kikiaosp_test/camera/aosp-kikiaosp-camera-sources.patch"
if git -C "$AOSP_ROOT" apply --check "$camera_sources_patch"; then
  git -C "$AOSP_ROOT" apply "$camera_sources_patch"
elif git -C "$AOSP_ROOT" apply --reverse --check "$camera_sources_patch"; then
  echo "camera source filegroup patch already applied"
else
  echo "camera source filegroup patch does not apply cleanly" >&2
  exit 1
fi
settings_kernel_patch="$REPO_ROOT/patches/aosp-kikiaosp-settings-kernel-version.patch"
if git -C "$AOSP_ROOT" apply --check "$settings_kernel_patch"; then
  git -C "$AOSP_ROOT" apply "$settings_kernel_patch"
elif git -C "$AOSP_ROOT" apply --reverse --check "$settings_kernel_patch"; then
  echo "SettingsLib kernel-version patch already applied"
else
  echo "SettingsLib kernel-version patch does not apply cleanly" >&2
  exit 1
fi
virgl_context_patch="$REPO_ROOT/patches/aosp-kikiaosp-virgl-context-before-prime.patch"
if git -C "$AOSP_ROOT" apply --check "$virgl_context_patch"; then
  git -C "$AOSP_ROOT" apply "$virgl_context_patch"
elif git -C "$AOSP_ROOT" apply --reverse --check "$virgl_context_patch"; then
  echo "VirGL context-before-PRIME patch already applied"
else
  echo "VirGL context-before-PRIME patch does not apply cleanly" >&2
  exit 1
fi
virgl_cpu_camera_patch="$REPO_ROOT/patches/aosp-kikiaosp-virgl-cpu-camera-yuv.patch"
if git -C "$AOSP_ROOT" apply --check "$virgl_cpu_camera_patch"; then
  git -C "$AOSP_ROOT" apply "$virgl_cpu_camera_patch"
elif git -C "$AOSP_ROOT" apply --reverse --check "$virgl_cpu_camera_patch"; then
  echo "VirGL CPU-camera-YUV patch already applied"
else
  echo "VirGL CPU-camera-YUV patch does not apply cleanly" >&2
  exit 1
fi
while IFS= read -r -d '' src; do
  rel=${src#"$REPO_ROOT/overlays/"}
  mkdir -p "$AOSP_ROOT/$(dirname "$rel")"
  cp -f "$src" "$AOSP_ROOT/$rel"
done < <(find "$REPO_ROOT/overlays" -type f -print0)
echo "KikiAOSP device tree and integration patches applied to $AOSP_ROOT"
