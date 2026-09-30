#!/usr/bin/env bash
set -uo pipefail
repo_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
aosp_root=${1:-$HOME/aosp-master}
build_jobs=${JOBS:-8}
log=${BUILD_LOG:-$repo_root/build-cp2a-theme-picker-$(date +%Y%m%d-%H%M%S).log}
exec > >(tee -a "$log") 2>&1
"$repo_root/scripts/sync-device-tree.sh" "$aosp_root" || exit 1
"$repo_root/scripts/audit-device-tree-profile.sh" "$repo_root" || exit 1
"$repo_root/scripts/audit-aosp-integration.sh" "$aosp_root" || exit 1
cd "$aosp_root" || exit 1
source build/envsetup.sh
lunch kikiaosp_test_arm64_phone-cp2a-userdebug || exit 1
m -j"$build_jobs" systemimage vendorimage
result=$?
printf '\nTHEME_BUILD_EXIT=%s\n' "$result"
exit "$result"
