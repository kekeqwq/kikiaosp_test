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
cd "$aosp_root"
source build/envsetup.sh
lunch kikiaosp_test_arm64_phone-cp2a-userdebug
m -j"${KIKI_BUILD_JOBS:-8}" vendorimage mkbootfs mkbootimg
python3 "$repo_root/scripts/build-boot-payload.py" \
    --aosp "$aosp_root" --kernel "$kernel" --output "$output" \
    --fstab "$repo_root/device/kiki/kikiaosp_test/fstab.gpt.ranchu"
cp "${OUT_DIR:-out}/target/product/kikiaosp_test/vendor.img" "$output/vendor.img"
sha256sum "$output/boot.img" "$output/ramdisk.img" "$output/vendor.img"
echo 'GPT_PROTOTYPE_BUILD_COMPLETE (development inputs, not a clean release)'
