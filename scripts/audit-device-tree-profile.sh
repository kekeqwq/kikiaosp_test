#!/usr/bin/env bash
set -euo pipefail

repo_root=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
device_dir="$repo_root/device/kiki/kikiaosp_test"
product="$device_dir/kikiaosp_test_arm64_phone.mk"
board="$device_dir/BoardConfig.mk"
fstab="$device_dir/fstab.ranchu"
native_rc="$device_dir/kiki-minimal-native.rc"
ranchu_rc="$device_dir/init.ranchu.rc"
app_bp="$device_dir/Android.bp"
app_manifest="$device_dir/apps/KikiWindowTest/AndroidManifest.xml"
app_source="$device_dir/apps/KikiWindowTest/src/com/kikiaosp/windowtest/MainActivity.java"
home_source="$device_dir/apps/KikiWindowTest/src/com/kikiaosp/windowtest/HomeActivity.java"
camera_bp="$device_dir/camera/Android.bp"
camera_source="$device_dir/camera/SurfaceCamera.cpp"
camera_policy="$device_dir/sepolicy/vendor/file_contexts"
adb_wait="$device_dir/kiki-adb-wait.sh"
settings_defaults="$device_dir/overlay/frameworks/base/packages/SettingsProvider/res/values/defaults.xml"
wallpaper_permissions="$device_dir/permissions/privapp-permissions-com.android.wallpaper.xml"

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
removal_count=$(grep -Ec '^[[:space:]]*PRODUCT_PACKAGES[[:space:]]+-=' "$product" || true)
[[ "$removal_count" -eq 2 ]] || fail 'only the two conflicting Ranchu camera packages may be removed'
require "$product" 'PRODUCT_PACKAGES -= android.hardware.camera.provider.ranchu'
require "$product" 'PRODUCT_PACKAGES -= android.hardware.camera.provider.ranchu_minigbm'

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

for package in Launcher3QuickStep Settings DocumentsUI Camera2 android.hardware.camera.provider.kikiaosp Gallery2 ThemePicker KikiCustomizationResources SystemUI LatinIME librs_jni com.android.hardware.power android.hardware.health-service.example com.android.hardware.audio; do
    require "$product" "    $package"
done
require "$product" 'persist.sys.timezone=Asia/Shanghai'
require "$device_dir/theme-resources/AndroidManifest.xml" 'package="com.android.customization.themes"'
require "$device_dir/theme-resources/res/values/palettes.xml" 'name="color_bundles"'
require "$device_dir/overlay/packages/apps/ThemePicker/res/values/kikiaosp_theme.xml" 'com.android.launcher3.grid.control'
require "$product" 'sys.use_memfd=true'
require "$product" 'TARGET_SCREEN_DENSITY := 288'
require "$device_dir/AndroidProducts.mk" 'kikiaosp_test_arm64_phone-cp2a-userdebug'
require "$repo_root/device/kiki/kikiaosp_test/release_config/release_configs/cp2a.textproto" 'name: "cp2a"'
require "$repo_root/device/kiki/kikiaosp_test/release_config/aconfig/cp2a/com.android.wm.shell/enable_taskbar_on_phones_flag_values.textproto" 'enable_taskbar_on_phones'
require "$repo_root/README.md" 'lunch kikiaosp_test_arm64_phone-cp2a-userdebug'
require "$device_dir/README.md" 'kikiaosp_test_arm64_phone-cp2a-userdebug'
require "$product" 'device/kiki/kikiaosp_test/permissions/privapp-permissions-com.android.wallpaper.xml:$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/permissions/privapp-permissions-com.android.wallpaper.xml'
require "$product" '$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/permissions/privapp-permissions-com.android.wallpaper.xml'
require "$wallpaper_permissions" '<privapp-permissions package="com.android.wallpaper">'
for permission in \
    android.permission.SET_WALLPAPER_DIM_AMOUNT \
    android.permission.READ_WALLPAPER_INTERNAL \
    android.permission.UPDATE_THEME_SETTINGS \
    android.permission.BIND_WALLPAPER \
    android.permission.SET_WALLPAPER_COMPONENT; do
    require "$wallpaper_permissions" "<permission name=\"$permission\" />"
done
require "$repo_root/patches/aosp-kikiaosp-retain-gallery2.patch" 'filter-out Gallery2'
require "$repo_root/patches/aosp-kikiaosp-settings-kernel-version.patch" 'formatKernelVersion_nixKernelWithDistroSuffix_shouldRemainAvailable'
require "$repo_root/scripts/apply-aosp-integration.sh" 'aosp-kikiaosp-settings-kernel-version.patch'
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
require "$settings_defaults" '<item name="def_device_font_scale" format="float" type="dimen">1.5</item>'
require "$device_dir/kiki-user-defaults.rc" 'start kiki_user_defaults'
require "$device_dir/kiki-user-defaults.sh" 'key_repeat_timeout 2000'
require "$device_dir/kiki-user-defaults.sh" 'key_repeat_delay 1000'

require "$board" 'TARGET_2ND_ARCH :='
require "$board" 'TARGET_SUPPORTS_32_BIT_APPS := false'
require "$board" 'TARGET_SUPPORTS_64_BIT_APPS := true'
require "$board" 'TARGET_COPY_OUT_PRODUCT := system/product'
require "$board" 'TARGET_COPY_OUT_SYSTEM_EXT := system/system_ext'
require "$board" 'device/kiki/kikiaosp_test/sepolicy/vendor'
require "$product" 'PRODUCT_BUILD_PRODUCT_IMAGE := false'
require "$product" 'PRODUCT_BUILD_SYSTEM_EXT_IMAGE := false'
! grep -Eq '^[[:space:]]*/dev/block/[^[:space:]]+[[:space:]]+/(product|system_ext)[[:space:]]' "$fstab" || \
    fail 'product and system_ext content are folded into the system image; do not mount separate images'
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
require "$device_dir/ueventd.kikiaosp.rc" '/dev/vport* 0666 system system'
require "$camera_bp" 'imports: ["device/generic/goldfish"]'
require "$camera_bp" ':kikiaosp_camera_aidl_common_sources'
require "$device_dir/camera/aosp-kikiaosp-camera-sources.patch" 'kikiaosp_camera_aidl_common_sources'
require "$device_dir/camera/android.hardware.camera.provider.kikiaosp.xml" 'internal/1'
require "$repo_root/scripts/apply-aosp-integration.sh" 'aosp-kikiaosp-camera-sources.patch'
require "$product" 'PRODUCT_SOONG_NAMESPACES += device/kiki/kikiaosp_test/camera'
require "$camera_source" 'closeCameraLocked()'
require "$camera_source" 'CLOSE\n'
require "$camera_source" 'reply == "CLOSED"'
require "$camera_source" 'if (owner == mOwner)'
require "$camera_source" 'Released real Surface'
require "$camera_source" 'mParams.isBackFacing'
require "$camera_policy" 'camera\.provider\.kikiaosp'
require "$product" 'frameworks/native/data/etc/android.hardware.camera.xml:vendor/etc/permissions/android.hardware.camera.xml'
require "$product" 'frameworks/native/data/etc/android.hardware.camera.front.xml:vendor/etc/permissions/android.hardware.camera.front.xml'

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
