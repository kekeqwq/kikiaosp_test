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
virtio_boot_patch="$REPO_ROOT/patches/aosp-kikiaosp-init-virtio-boot-uuid.patch"
if git -C "$AOSP_ROOT" apply --check "$virtio_boot_patch"; then
  git -C "$AOSP_ROOT" apply "$virtio_boot_patch"
elif git -C "$AOSP_ROOT" apply --reverse --check "$virtio_boot_patch"; then
  echo "virtio boot-partition UUID patch already applied"
else
  echo "virtio boot-partition UUID patch does not apply cleanly" >&2
  exit 1
fi
exact_storage_patch="$REPO_ROOT/patches/aosp-kikiaosp-exact-storage-size.patch"
if git -C "$AOSP_ROOT" apply --check "$exact_storage_patch"; then
  git -C "$AOSP_ROOT" apply "$exact_storage_patch"
elif git -C "$AOSP_ROOT" apply --reverse --check "$exact_storage_patch"; then
  echo "Exact KikiAOSP storage-capacity patch already applied"
else
  echo "Exact KikiAOSP storage-capacity patch does not apply cleanly" >&2
  exit 1
fi
category_patch="$REPO_ROOT/patches/aosp-kikiaosp-storage-category-floor.patch"
if git -C "$AOSP_ROOT" apply --check "$category_patch"; then
  git -C "$AOSP_ROOT" apply "$category_patch"
elif git -C "$AOSP_ROOT" apply --reverse --check "$category_patch"; then
  echo "KikiAOSP storage-category patch already applied"
else
  echo "KikiAOSP storage-category patch does not apply cleanly" >&2
  exit 1
fi
no_wipe_patch="$REPO_ROOT/patches/aosp-kikiaosp-ota-no-userdata-wipe.patch"
if git -C "$AOSP_ROOT" apply --check "$no_wipe_patch"; then
  git -C "$AOSP_ROOT" apply "$no_wipe_patch"
elif git -C "$AOSP_ROOT" apply --reverse --check "$no_wipe_patch"; then
  echo "Kiki native no-wipe gate already applied"
else
  echo "Kiki native no-wipe gate does not apply cleanly" >&2; exit 1
fi
audio_pcm_patch="$REPO_ROOT/patches/aosp-kikiaosp-synchronous-pcm.patch"
if git -C "$AOSP_ROOT" apply --check "$audio_pcm_patch"; then
  git -C "$AOSP_ROOT" apply "$audio_pcm_patch"
elif git -C "$AOSP_ROOT" apply --reverse --check "$audio_pcm_patch"; then
  echo "Kiki synchronous PCM patch already applied"
else
  echo "Kiki synchronous PCM patch does not apply cleanly" >&2
  exit 1
fi
while IFS= read -r -d '' src; do
  rel=${src#"$REPO_ROOT/overlays/"}
  mkdir -p "$AOSP_ROOT/$(dirname "$rel")"
  cp -f "$src" "$AOSP_ROOT/$rel"
done < <(find "$REPO_ROOT/overlays" -type f -print0)
echo "KikiAOSP device tree and integration patches applied to $AOSP_ROOT"
