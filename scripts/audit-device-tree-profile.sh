#!/usr/bin/env bash
set -euo pipefail

repo_root=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
device_dir="$repo_root/device/kiki/kikiaosp_test"
product="$device_dir/kikiaosp_test_arm64_phone.mk"
board="$device_dir/BoardConfig.mk"
native_rc="$device_dir/kiki-minimal-native.rc"
ranchu_rc="$device_dir/init.ranchu.rc"
app_bp="$device_dir/Android.bp"
app_manifest="$device_dir/apps/KikiWindowTest/AndroidManifest.xml"
app_source="$device_dir/apps/KikiWindowTest/src/com/kikiaosp/windowtest/MainActivity.java"
home_source="$device_dir/apps/KikiWindowTest/src/com/kikiaosp/windowtest/HomeActivity.java"
adb_wait="$device_dir/kiki-adb-wait.sh"
settings_defaults="$device_dir/overlay/frameworks/base/packages/SettingsProvider/res/values/defaults.xml"

fail() { echo "device-tree profile audit: $*" >&2; exit 1; }
require() { grep -Fq -- "$2" "$1" || fail "missing '$2' in $1"; }

[[ -f "$product" && -f "$board" && -f "$native_rc" && -f "$ranchu_rc" ]] || fail "incomplete device tree at $device_dir"

require "$product" '$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)'
require "$product" '$(call inherit-product, $(SRC_TARGET_DIR)/product/core_minimal.mk)'
require "$product" '$(call inherit-product-if-exists, frameworks/base/data/fonts/fonts.mk)'
require "$product" '$(call inherit-product-if-exists, external/roboto-fonts/fonts.mk)'
require "$product" '$(call inherit-product-if-exists, external/noto-fonts/fonts.mk)'
require "$product" 'PRODUCT_COMPRESSED_APEX := false'
! grep -Fq 'kiki-libconnectivity-native' "$product" || \
    fail 'do not duplicate the tethering APEX library into /system/lib64'
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
    'ro.kikiaosp.telephony_registry=true' \
    'debug.sf.nobootanimation=1' \
    'ro.kikiaosp.battery_service=true'; do
    require "$product" "$property"
done

for package in Launcher3QuickStep Settings SystemUI LatinIME librs_jni com.android.hardware.power android.hardware.health-service.example com.android.hardware.audio; do
    require "$product" "    $package"
done
! grep -Fq '    KikiWindowTest' "$product" || \
    fail 'KikiWindowTest is a regression fixture, not a product package'
require "$product" 'device/kiki/kikiaosp_test/audio/audio_policy_configuration.xml:vendor/etc/audio_policy_configuration.xml'
require "$product" 'hardware/interfaces/audio/aidl/default/audio_effects_config.xml:vendor/etc/audio_effects_config.xml'
require "$product" 'frameworks/av/services/audiopolicy/config/r_submix_audio_policy_configuration.xml:vendor/etc/r_submix_audio_policy_configuration.xml'
require "$product" 'frameworks/av/services/audiopolicy/config/bluetooth_with_le_audio_policy_configuration_7_0.xml:vendor/etc/bluetooth_with_le_audio_policy_configuration_7_0.xml'
require "$device_dir/audio/audio_policy_configuration.xml" '<module name="primary"'
require "$device_dir/audio/audio_policy_configuration.xml" 'AUDIO_DEVICE_OUT_SPEAKER'
require "$device_dir/audio/audio_policy_configuration.xml" 'r_submix_audio_policy_configuration.xml'
require "$device_dir/audio/audio_policy_configuration.xml" 'bluetooth_with_le_audio_policy_configuration_7_0.xml'
require "$app_bp" 'name: "KikiWindowTest"'
require "$app_manifest" 'package="com.kikiaosp.windowtest"'
require "$app_manifest" 'android:name=".HomeActivity"'
require "$app_manifest" 'android:label="KikiAOSP Home"'
require "$app_manifest" 'android.intent.category.HOME'
require "$app_source" 'finish()'
require "$app_source" 'ValueAnimator'
require "$home_source" 'Installed apps'
require "$home_source" 'FLAG_KEEP_SCREEN_ON'
require "$home_source" 'startActivity(launch)'
require "$home_source" 'queryIntentActivities(launcherIntent, 0)'
require "$home_source" 'Intent.CATEGORY_LAUNCHER'
require "$adb_wait" 'cmd package set-home-activity --user 0 com.android.launcher3'
! grep -Fq 'am start --user 0 -n com.kikiaosp.windowtest' "$adb_wait" || \
    fail 'do not auto-start the regression APK'
require "$adb_wait" 'settings put global device_provisioned 1'
require "$adb_wait" 'settings --user 0 put secure user_setup_complete 1'
require "$settings_defaults" '<bool name="def_device_provisioned">true</bool>'
require "$settings_defaults" '<bool name="def_user_setup_complete">true</bool>'

require "$board" 'TARGET_2ND_ARCH :='
require "$board" 'TARGET_SUPPORTS_32_BIT_APPS := false'
require "$board" 'TARGET_SUPPORTS_64_BIT_APPS := true'
require "$product" 'PRODUCT_SOONG_NAMESPACES += device/generic/goldfish'
require "$product" 'com.android.hardware.graphics.composer.ranchu'
! grep -Fq 'android.hardware.graphics.composer3-service.ranchu' "$product" || \
    fail 'use the upstream Ranchu composer APEX, not the raw service binary'
require "$product" 'android.hardware.graphics.allocator-service.minigbm'
require "$product" 'mapper.minigbm'
require "$product" 'vulkan.pastel'
require "$product" 'device/kiki/kikiaosp_test/ueventd.kikiaosp.rc:vendor/etc/ueventd.rc'
require "$device_dir/ueventd.kikiaosp.rc" '/dev/dri/card0 0660 system graphics'
require "$device_dir/ueventd.kikiaosp.rc" '/dev/dri/renderD128 0666 system graphics'

require "$product" 'ro.vendor.hwcomposer.display_finder_mode=drm'
for property_bridge in \
    'setprop ro.hardware.egl ${ro.boot.hardwareegl:-emulation}' \
    'setprop ro.hardware.vulkan ${ro.boot.hardware.vulkan}' \
    'setprop ro.hardware.gralloc ${ro.boot.hardware.gralloc:-ranchu}' \
    'setprop dalvik.vm.heapgrowthlimit ${ro.boot.dalvik.vm.heapgrowthlimit:-256m}' \
    'setprop dalvik.vm.heapsize ${ro.boot.dalvik.vm.heapsize:-512m}' \
    'setprop debug.renderengine.backend ${ro.boot.debug.renderengine.backend:-skiaglthreaded}'; do
    require "$ranchu_rc" "$property_bridge"
done
if grep -Eq '^[[:space:]]+stop[[:space:]]+' "$native_rc"; then
    fail 'Kiki init must not stop Android native services'
fi

echo "device-tree profile audit passed: curated AOSP core, Android UI APK set, full-startup mode, no Kiki native-service stop rules"
