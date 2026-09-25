#!/usr/bin/env bash
set -euo pipefail

repo_root=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
device_dir="$repo_root/device/kiki/kikiaosp_test"
product="$device_dir/kikiaosp_test_arm64_phone.mk"
board="$device_dir/BoardConfig.mk"
native_rc="$device_dir/kiki-minimal-native.rc"
app_bp="$device_dir/Android.bp"
app_manifest="$device_dir/apps/KikiWindowTest/AndroidManifest.xml"
app_source="$device_dir/apps/KikiWindowTest/src/com/kikiaosp/windowtest/MainActivity.java"

fail() { echo "device-tree profile audit: $*" >&2; exit 1; }
require() { grep -Fq -- "$2" "$1" || fail "missing '$2' in $1"; }

[[ -f "$product" && -f "$board" && -f "$native_rc" ]] || fail "incomplete device tree at $device_dir"

require "$product" '$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)'
require "$product" '$(call inherit-product, $(SRC_TARGET_DIR)/product/core_minimal.mk)'
require "$product" 'ZYGOTE_FORCE_64 := true'
! grep -Fq '$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_arm64.mk)' "$product" || \
    fail 'the broad AOSP ARM64 GSI product must not be inherited'
! grep -Fq 'KIKI_NONCORE_PACKAGES' "$product" || fail 'remove the broad package-minus policy'
if grep -Eq '^[[:space:]]*PRODUCT_PACKAGES[[:space:]]+-=' "$product"; then
    fail 'remove broad package-minus assignments'
fi

for property in \
    'ro.kikiaosp.bootstrap_only=false' \
    'ro.kikiaosp.minimal_services=false' \
    'ro.kikiaosp.single_mount_namespace=true' \
    'ro.kikiaosp.overlay_manager=true' \
    'ro.kikiaosp.sensorless=true' \
    'ro.kikiaosp.sensor_privacy=true' \
    'ro.kikiaosp.role_manager=true' \
    'ro.kikiaosp.usage_stats=true' \
    'ro.kikiaosp.telephony_registry=false' \
    'ro.kikiaosp.battery_service=false'; do
    require "$product" "$property"
done

for package in Launcher3QuickStep Settings SystemUI LatinIME KikiWindowTest; do
    require "$product" "    $package"
done
require "$app_bp" 'name: "KikiWindowTest"'
require "$app_manifest" 'package="com.kikiaosp.windowtest"'
require "$app_source" 'finish()'
require "$app_source" 'ValueAnimator'

require "$board" 'TARGET_2ND_ARCH :='
require "$board" 'TARGET_SUPPORTS_32_BIT_APPS := false'
require "$board" 'TARGET_SUPPORTS_64_BIT_APPS := true'
require "$product" 'com.android.hardware.graphics.composer.ranchu'
require "$product" 'android.hardware.graphics.allocator-service.minigbm'
require "$product" 'mapper.minigbm'
require "$product" 'vulkan.pastel'

if grep -Eq '^[[:space:]]+stop[[:space:]]+' "$native_rc"; then
    fail 'Kiki init must not stop Android native services'
fi

echo "device-tree profile audit passed: curated AOSP core, Android UI APK set, full-startup mode, no Kiki native-service stop rules"
