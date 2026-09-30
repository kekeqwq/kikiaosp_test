#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
if [[ $# != 3 ]]; then
    echo 'Usage: bash scripts/build-gpt-prototype.sh AOSP_ROOT KERNEL_IMAGE NEW_OUTPUT_DIRECTORY' >&2
    exit 2
fi
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
aosp_root=$(realpath "$1")
kernel=$(realpath "$2")
output=$(realpath -m "$3")
[[ ! -e $output ]] || { echo 'Output must be a new directory.' >&2; exit 2; }
bash "$repo_root/scripts/sync-device-tree.sh" "$aosp_root"
uuid_patch="$repo_root/patches/aosp-kikiaosp-init-virtio-boot-uuid.patch"
if git -C "$aosp_root" apply --check "$uuid_patch"; then
    git -C "$aosp_root" apply "$uuid_patch"
elif ! git -C "$aosp_root" apply --reverse --check "$uuid_patch"; then
    echo 'Tracked virtio UUID patch does not match AOSP init.' >&2
    exit 1
fi
storage_patch="$repo_root/patches/aosp-kikiaosp-exact-storage-size.patch"
if git -C "$aosp_root" apply --check "$storage_patch"; then
    git -C "$aosp_root" apply "$storage_patch"
elif ! git -C "$aosp_root" apply --reverse --check "$storage_patch"; then
    echo 'Tracked exact storage-capacity patch does not match AOSP framework.' >&2
    exit 1
fi
cd "$aosp_root"
source build/envsetup.sh
lunch kikiaosp_test_arm64_phone-cp2a-userdebug
m -j"${KIKI_BUILD_JOBS:-8}" init_first_stage init_second_stage systemimage vendorimage mkbootfs mkbootimg
python3 "$repo_root/scripts/build-boot-payload.py" \
    --aosp "$aosp_root" --kernel "$kernel" --output "$output" \
    --fstab "$repo_root/device/kiki/kikiaosp_test/fstab.gpt.ranchu"
cp "${OUT_DIR:-out}/target/product/kikiaosp_test/vendor.img" "$output/vendor.img"
cp "${OUT_DIR:-out}/target/product/kikiaosp_test/system.img" "$output/system.img"
sha256sum "$output/boot.img" "$output/ramdisk.img" "$output/vendor.img" "$output/system.img"
echo 'GPT_PROTOTYPE_BUILD_COMPLETE (development inputs, not a clean release)'
