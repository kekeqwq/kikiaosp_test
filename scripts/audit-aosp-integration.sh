#!/usr/bin/env bash
set -euo pipefail
AOSP_ROOT=${1:-}
REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [[ -z "$AOSP_ROOT" || ! -d "$AOSP_ROOT/.repo" ]]; then echo "usage: $0 /path/to/aosp-master" >&2; exit 2; fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
awk '/^diff --git a\// {print $3}' "$REPO_ROOT/patches/aosp-working-tree.patch" |
  sed 's#^a/##' | sort -u > "$tmp/expected"
( cd "$AOSP_ROOT"; repo forall -c 'git diff --name-only | sed "s#^#$REPO_PATH/#"' ) | sed '/^$/d' | sort -u > "$tmp/actual"
if ! diff -u "$tmp/expected" "$tmp/actual"; then echo "AOSP tracked changes do not exactly match kikiaosp_test/patches" >&2; exit 1; fi
patch -d "$AOSP_ROOT" -p1 --dry-run --reverse --batch \
  < "$REPO_ROOT/patches/aosp-working-tree.patch" >/dev/null || {
  echo "AOSP source does not exactly match patches/aosp-working-tree.patch" >&2
  exit 1
}
system_server_src="$AOSP_ROOT/frameworks/base/services/java/com/android/server/SystemServer.java"
if ! grep -Fq 'if (!kikiMinimalServices || SystemProperties.getBoolean("ro.kikiaosp.telephony_registry", false))' "$system_server_src"; then
  echo "Full Framework startup must retain TelephonyRegistry required by Connectivity" >&2
  exit 1
fi
role_block=$(sed -n '/t.traceBegin("StartRoleManagerService")/,+12p' "$system_server_src")
printf '%s\n' "$role_block" | awk '
  /startService\(ROLE_SERVICE_CLASS\)/ { role = NR }
  /traceBegin\("StartSupervisionService"\)/ { supervision = NR }
  /startService\(SupervisionService.Lifecycle.class\)/ { start = NR }
  END { exit !(role > 0 && supervision > role && start > supervision) }
' || {
  echo "Kiki must start SupervisionService after RoleService; RoleController requires its Binder API" >&2
  exit 1
}
minimal_ready_block=$(sed -n '/kmsg("minimal-services-shortcut");/,/return;/p' "$system_server_src")
printf '%s\n' "$minimal_ready_block" | awk '
  /mSystemServiceManager.startService\(InputMethodManagerService.Lifecycle.class\)/ { input_method = NR }
  /mSystemServiceManager.startService\(UiModeManagerService.class\)/ { ui_mode = NR }
  /mSystemServiceManager.startService\(StorageManagerService.Lifecycle.class\)/ { storage = NR }
  /mSystemServiceManager.startService\(GrammaticalInflectionService.class\)/ { grammatical = NR }
  /mSystemServiceManager.startService\(AppHibernationService.class\)/ { app_hibernation = NR }
  /DexOptHelper.initializeArtManagerLocal\(context, mPackageManagerService\)/ { art_manager = NR }
  /t.traceBegin\("KikiStartStatusBarManagerService"\)/ { status_bar = NR }
  /mSystemServiceManager.startService\(NotificationManagerService.class\)/ { notification = NR }
  /startBootPhase\(t, SystemService.PHASE_SYSTEM_SERVICES_READY\)/ { ready_phase = NR }
  /wm.systemReady\(\)/ { window_manager = NR }
  /mSystemServiceManager.startService\(PermissionPolicyService.class\)/ { permission_policy = NR }
  /mPackageManagerService.waitForAppDataPrepared\(\)/ { app_data = NR }
  /mPackageManagerService.systemReady\(\)/ { package_manager = NR }
  /mDisplayManagerService.systemReady\(false\)/ { display_manager = NR }
  /mActivityManagerService.systemReady\(/ { activity_manager = NR }
  /PHASE_ACTIVITY_MANAGER_READY\)/ { activity_phase = NR }
  /PHASE_THIRD_PARTY_APPS_CAN_START\)/ { third_party_phase = NR }
  /startSystemUi\(context, kikiWindowManager\)/ { system_ui = NR }
  END { exit !(input_method > 0 && ui_mode > input_method && storage > ui_mode && grammatical > storage && app_hibernation > grammatical && art_manager > app_hibernation && status_bar > art_manager && notification > status_bar && ready_phase > notification && window_manager > ready_phase && permission_policy > window_manager && app_data > permission_policy && package_manager > app_data && display_manager > package_manager && activity_manager > display_manager && activity_phase > activity_manager && third_party_phase > activity_phase && system_ui > third_party_phase) }
' || {
  echo "Kiki minimal path must start IMMS/RoleManager dependencies and UI services before phase 500, then complete phases 550/600 before SystemUI" >&2
  exit 1
}
system_service_manager_src="$AOSP_ROOT/frameworks/base/services/core/java/com/android/server/SystemServiceManager.java"
service_registry_src="$AOSP_ROOT/frameworks/base/core/java/android/app/SystemServiceRegistry.java"
if ! grep -Fq 'registerService(Context.TETHERING_SERVICE, TetheringManager.class,' "$service_registry_src"; then
  echo "NetworkStatsService requires the stock TetheringManager registry entry during phase 550" >&2
  exit 1
fi
for service in UiModeManagerService StorageManagerService RoleService InputMethodManagerService \
  NotificationManagerService SupervisionService PermissionPolicyService AppHibernationService \
  GrammaticalInflectionService; do
  grep -Fq "n.contains(\"$service\")" "$system_service_manager_src" || {
    echo "Kiki minimal boot-phase allowlist is missing $service" >&2
    exit 1
  }
done
mount_idler_src="$AOSP_ROOT/frameworks/base/services/core/java/com/android/server/MountServiceIdler.java"
grep -A5 -F 'JobScheduler tm = (JobScheduler) context.getSystemService' "$mount_idler_src" | \
  grep -Fq 'if (tm == null)' && \
grep -Fq 'Skipping mount idle pass because JobScheduler is unavailable' "$mount_idler_src" || {
  echo "Minimal profile must skip the optional mount-idle job when JobScheduler is omitted" >&2
  exit 1
}
smart_mount_idler_src="$AOSP_ROOT/frameworks/base/services/core/java/com/android/server/SmartStorageMaintIdler.java"
grep -A4 -F 'JobScheduler tm = context.getSystemService(JobScheduler.class);' "$smart_mount_idler_src" | \
  grep -Fq 'if (tm == null)' && \
grep -Fq 'Skipping smart storage idle pass because JobScheduler is unavailable' "$smart_mount_idler_src" || {
  echo "Minimal profile must skip optional smart storage maintenance when JobScheduler is omitted" >&2
  exit 1
}
input_manager_src="$AOSP_ROOT/frameworks/base/services/core/java/com/android/server/input/InputManagerService.java"
grep -A8 -F 'if (AttentionManagerService.isInteractionProviderServiceEnabled(mContext))' "$input_manager_src" | \
  grep -Fq 'if (interactionProvider != null)' && \
grep -Fq 'Skipping optional interaction provider; service is unavailable' "$input_manager_src" || {
  echo "Kiki minimal InputManager must tolerate an omitted optional AttentionManagerService" >&2
  exit 1
}
product_mk="$AOSP_ROOT/device/kiki/kikiaosp_test/kikiaosp_test_arm64_phone.mk"
grep -Fq '$(SRC_TARGET_DIR)/product/core_minimal.mk' "$product_mk" && \
grep -Fq 'ro.kikiaosp.bootstrap_only=false' "$product_mk" && \
grep -Fq 'ro.kikiaosp.minimal_services=false' "$product_mk" && \
grep -Fq '    Launcher3QuickStep' "$product_mk" && \
grep -Fq '    Settings' "$product_mk" && \
! grep -Fq '    KikiWindowTest' "$product_mk" && \
! grep -Fq 'inherit-product, $(SRC_TARGET_DIR)/product/aosp_arm64.mk' "$product_mk" && \
! grep -Fq 'KIKI_NONCORE_PACKAGES' "$product_mk" || {
  echo "Kiki product must use the curated core/UI profile, not the broad GSI package-minus profile" >&2
  exit 1
}
linker_config_json="$AOSP_ROOT/system/core/rootdir/etc/linker.config.json"
grep -Fq '"libcom.android.tethering.connectivity_native.so"' "$linker_config_json" || {
  echo "Kiki system namespace must require the tethering APEX library used by libandroid.so" >&2
  exit 1
}
grep -Fq '"libicu_jni.so"' "$linker_config_json" || {
  echo "Kiki default namespace must require libicu_jni.so from the i18n APEX for zygote" >&2
  exit 1
}
for art_jni_lib in libicu_jni.so libjavacore.so libopenjdk.so; do
  if grep -Fq "\"/system/lib64/$art_jni_lib\"" "$AOSP_ROOT/art/runtime/runtime.cc"; then
    echo "ART must load $art_jni_lib through its APEX linker namespace, not an absent system path" >&2
    exit 1
  fi
done
grep -Fq 'PRODUCT_SOONG_NAMESPACES += device/generic/goldfish' "$product_mk" && \
grep -Fq 'com.android.hardware.graphics.composer.ranchu' "$product_mk" && \
! grep -Fq 'android.hardware.graphics.composer3-service.ranchu' "$product_mk" || {
  echo "Kiki must export the Goldfish namespace root and install the upstream Ranchu HWC3 vendor APEX" >&2
  exit 1
}
if ! grep -Fq 'ro.vendor.hwcomposer.display_finder_mode=drm' "$product_mk"; then
  echo "Kiki Ranchu HWC3 must select DRM finder for upstream QEMU virtio-gpu" >&2
  exit 1
fi
if ! grep -Fq '    librs_jni' "$product_mk"; then
  echo "Kiki core product must install librs_jni required by Zygote's RenderScript class preload" >&2
  exit 1
fi
if ! grep -Fq '    com.android.hardware.power' "$product_mk"; then
  echo "Kiki Android 17 HintManager requires the upstream Goldfish virtual Power HAL" >&2
  exit 1
fi
zygote_rc="$AOSP_ROOT/system/core/rootdir/init.zygote64.rc"
if grep -Eq '^[[:space:]]*setenv[[:space:]]+SYSTEMSERVERCLASSPATH' "$zygote_rc"; then
  echo "Zygote must retain derive_classpath's generated APEX system-server classpath" >&2
  exit 1
fi
init_rc="$AOSP_ROOT/system/core/rootdir/init.rc"
if ! grep -Fq '    trigger load-bpf-programs' "$init_rc"; then
  echo "Standard BPF loader trigger must run before Zygote so netd can start" >&2
  exit 1
fi
allocator_rc="$AOSP_ROOT/external/minigbm/cros_gralloc/aidl/allocator.rc"
if ! grep -Fxq '    setenv KIKI_ALLOCATOR 1' "$allocator_rc"; then
  echo "Kiki allocator must open the primary DRM node for dumb-buffer allocation" >&2
  exit 1
fi
if ! grep -Fxq 'service kiki_logdump /system/bin/sh -c "sleep 90; logcat -b all -d -v brief"' "$init_rc" || \
   ! grep -Fxq '    stdio_to_kmsg' "$init_rc" || \
   ! grep -Fxq '    start kiki_logdump' "$init_rc"; then
  echo "Kiki runtime logcat must use init stdio_to_kmsg and dump once after startup" >&2
  exit 1
fi
ranchu_init="$REPO_ROOT/device/kiki/kikiaosp_test/init.ranchu.rc"
for property_bridge in \
  'setprop ro.hardware.egl ${ro.boot.hardwareegl:-emulation}' \
  'setprop ro.hardware.vulkan ${ro.boot.hardware.vulkan}' \
  'setprop ro.hardware.gralloc ${ro.boot.hardware.gralloc:-ranchu}' \
  'setprop dalvik.vm.heapgrowthlimit ${ro.boot.dalvik.vm.heapgrowthlimit:-256m}' \
  'setprop dalvik.vm.heapsize ${ro.boot.dalvik.vm.heapsize:-512m}' \
  'setprop debug.renderengine.backend ${ro.boot.debug.renderengine.backend:-skiaglthreaded}'; do
  grep -Fq "$property_bridge" "$ranchu_init" || {
    echo "Ranchu early-init property bridge missing: $property_bridge" >&2
    exit 1
  }
done
! grep -Fq 'kiki-libconnectivity-native' "$product_mk" || {
  echo "Do not duplicate the tethering APEX library into /system/lib64" >&2
  exit 1
}
if grep -Eq '^[[:space:]]+stop[[:space:]]+' \
    "$REPO_ROOT/device/kiki/kikiaosp_test/kiki-minimal-native.rc"; then
  echo "Kiki init policy must not disable Android native services" >&2
  exit 1
fi
grep -Fq 'ro.kikiaosp.sensorless=true' "$product_mk" && \
grep -Fq 'ro.kikiaosp.sensor_privacy=true' "$product_mk" || {
  echo "Kiki native-window product must retain sensorless mode while publishing SensorPrivacyService" >&2
  exit 1
}
grep -Fqx '    ro.kikiaosp.usage_stats=true \' "$product_mk" || {
  echo "Kiki native-window product must enable usage-stats core services" >&2
  exit 1
}
grep -Fq 'ro.kikiaosp.sensor_privacy=true' "$REPO_ROOT/scripts/repack-apk-window-test.sh" && \
grep -A4 -F 't.traceBegin("StartSensorPrivacyService")' "$system_server_src" | \
  grep -Fq 'if (SystemProperties.getBoolean("ro.kikiaosp.sensor_privacy", false))' || {
  echo "Kiki image must publish SensorPrivacyService required by AppOps without starting sensor HALs" >&2
  exit 1
}
sensor_provider_src="$AOSP_ROOT/frameworks/base/services/core/java/com/android/server/policy/DeviceStateProviderImpl.java"
grep -Fq 'if (!sensorsToListenTo.isEmpty()) {' "$sensor_provider_src" || {
  echo "DeviceStateProvider still creates SensorManager with no sensor requirements" >&2
  exit 1
}
stage_src="$AOSP_ROOT/external/selinux/libselinux/src/compute_av.c"
for marker in \
  'log_kiki_compute_av_stage("mount-pointer", -1, ENOENT, NULL, NULL);' \
  'log_kiki_compute_av_stage("open", fd, errno, path, NULL);' \
  'log_kiki_compute_av_stage("malloc", -1, errno, path, NULL);' \
  'log_kiki_compute_av_stage("format", -1, errno, path, NULL);' \
  'log_kiki_compute_av_stage("write", ret, errno, path, NULL);' \
  'log_kiki_compute_av_stage("read", ret, errno, path, NULL);' \
  'log_kiki_compute_av_stage("parse", ret, errno, path, buf);'; do
  grep -Fq "$marker" "$stage_src" || {
    echo "AOSP SELinux stage diagnostic is incomplete: $marker" >&2
    exit 1
  }
done
grep -Fq 'statfs(selinux_mnt, &mount_stat)' "$stage_src" || {
  echo "AOSP SELinux mount-type diagnostic is incomplete" >&2
  exit 1
}
grep -Fq '#include <sys/vfs.h>' "$stage_src" || {
  echo "AOSP SELinux mount-type diagnostic header is missing" >&2
  exit 1
}
grep -Fq 'failure-thread pid=%d mount_ns=%s' "$stage_src" || {
  echo "AOSP SELinux failing-thread namespace diagnostic is missing" >&2
  exit 1
}
mount_ns_src="$AOSP_ROOT/system/core/init/mount_namespace.cpp"
for marker in \
  'LogSelinuxMountView("setup-enter")' \
  'LogSelinuxMountView("before-unshare")' \
  'LogSelinuxMountView("after-unshare")' \
  'LogSelinuxMountView("after-setns-bootstrap")'; do
  grep -Fq "$marker" "$mount_ns_src" || {
    echo "AOSP mount-namespace diagnostic is incomplete: $marker" >&2
    exit 1
  }
done
grep -Fq 'Readlink("/proc/thread-self/ns/mnt"' "$mount_ns_src" || {
  echo "AOSP mount-namespace diagnostic does not use the calling thread's namespace" >&2
  exit 1
}
for marker in \
  'LogInitThreadSelinuxMountViews("before-unshare")' \
  'LogInitThreadSelinuxMountViews("after-setns-bootstrap")' \
  'KIKI-MNTNS-THREAD stage=' \
  'opendir("/proc/1/task")'; do
  grep -Fq "$marker" "$mount_ns_src" || {
    echo "AOSP init-thread mount diagnostic is incomplete: $marker" >&2
    exit 1
  }
done
grep -Fq 'GetBoolProperty("ro.kikiaosp.single_mount_namespace", false)' "$mount_ns_src" || {
  echo "AOSP single-mount-namespace opt-in is missing" >&2
  exit 1
}
grep -Fq 'ro.kikiaosp.single_mount_namespace=true' \
  "$REPO_ROOT/device/kiki/kikiaosp_test/kikiaosp_test_arm64_phone.mk" || {
  echo "Kiki product single-mount-namespace property is missing" >&2
  exit 1
}
grep -Fq 'service.sf.prime_shader_cache=false' \
  "$REPO_ROOT/device/kiki/kikiaosp_test/kikiaosp_test_arm64_phone.mk" || {
  echo "Kiki SurfaceFlinger shader-prewarm workaround is missing" >&2
  exit 1
}
for marker in \
  'export ANDROID_ROOT /system' \
  'export ANDROID_DATA /data' \
  'export ANDROID_ASSETS /system/app' \
  'export ANDROID_STORAGE /storage' \
  'export ANDROID_ART_ROOT /apex/com.android.art' \
  'export ANDROID_I18N_ROOT /apex/com.android.i18n' \
  'export ANDROID_TZDATA_ROOT /apex/com.android.tzdata'; do
  grep -Fq "$marker" "$REPO_ROOT/device/kiki/kikiaosp_test/kiki-minimal-native.rc" || {
    echo "Kiki standard init environment is incomplete: $marker" >&2
    exit 1
  }
done
grep -A1 -F 'setprop vold.decrypt trigger_restart_framework' \
  "$AOSP_ROOT/system/core/rootdir/init.rc" | grep -Fq 'trigger nonencrypted' || {
  echo "AOSP post-fs-data path does not trigger the nonencrypted boot action" >&2
  exit 1
}
grep -Fq 'trigger nonencrypted' "$REPO_ROOT/scripts/repack-apk-window-test.sh" && \
grep -Fq 'kiki-minimal-native.rc' "$REPO_ROOT/scripts/repack-apk-window-test.sh" || {
  echo "APK repacker does not stage the minimal-init boot-contract fixes" >&2
  exit 1
}
system_server_src="$AOSP_ROOT/frameworks/base/services/java/com/android/server/SystemServer.java"
activity_thread_src="$AOSP_ROOT/frameworks/base/core/java/android/app/ActivityThread.java"
grep -Fq 'public void initializeSystemApplication()' "$activity_thread_src" && \
grep -Fq 'activityThread.initializeSystemApplication();' "$system_server_src" || {
  echo "system Application must be initialized from SystemServer after context setup" >&2
  exit 1
}
grep -A3 -F 't.traceBegin("StartAccountManagerService")' "$system_server_src" | \
  grep -Fq 'mSystemServiceManager.startService(AccountManagerService.Lifecycle.class)' || {
  echo "AccountManagerService is required before the minimal ContentService" >&2
  exit 1
}
grep -A3 -F 't.traceBegin("StartContentService")' "$system_server_src" | \
  grep -Fq 'mSystemServiceManager.startService(ContentService.Lifecycle.class)' || {
  echo "Kiki minimal profile must publish ContentService for Settings observers" >&2
  exit 1
}
if grep -Fq 'else { kmsg("skip-account-manager"); }' "$system_server_src" || \
    grep -Fq 'else { kmsg("skip-content-service"); }' "$system_server_src"; then
  echo "Kiki minimal profile still skips provider observer dependencies" >&2
  exit 1
fi
grep -A9 -F 't.traceBegin("InstallSystemProviders")' "$system_server_src" | \
  grep -Fq 'installSystemProviders();' || {
  echo "Kiki minimal profile must install SettingsProvider before WindowManagerService" >&2
  exit 1
}
if grep -B1 -F 't.traceBegin("InstallSystemProviders")' "$system_server_src" | \
    grep -Fq 'if (!kikiMinimalServices)'; then
  echo "Kiki minimal profile still gates system provider installation" >&2
  exit 1
fi
grep -A6 -F 'mActivityManagerService.getContentProviderHelper().installSystemProviders();' \
  "$system_server_src" | grep -Fq 'if (!kikiMinimalServices)' || {
  echo "Kiki minimal profile must keep optional DeviceConfig gated separately" >&2
  exit 1
}
if grep -Fq 'else { kmsg("skip-system-providers"); }' "$system_server_src"; then
  echo "Kiki minimal profile still skips required system providers" >&2
  exit 1
fi
grep -A3 -F 't.traceBegin("DeviceStateManagerService")' "$system_server_src" | \
  grep -Fq 'mSystemServiceManager.startService(DeviceStateManagerService.class)' || {
  echo "Kiki core DeviceStateManagerService start is missing" >&2
  exit 1
}
if grep -Fq 'else { kmsg("skip-device-state"); }' "$system_server_src"; then
  echo "Kiki minimal-services path still skips DeviceStateManagerService" >&2
  exit 1
fi
grep -A3 -F 't.traceBegin("StartAlarmManagerService")' "$system_server_src" | \
  grep -Fq 'mSystemServiceManager.startService(AlarmManagerService.class)' || {
  echo "Kiki minimal startup must keep the core AlarmManagerService available" >&2
  exit 1
}
grep -A3 -F 't.traceBegin("KikiStartGrammaticalInflectionService")' "$system_server_src" | \
  grep -Fq 'mSystemServiceManager.startService(GrammaticalInflectionService.class)' || {
  echo "Kiki minimal startup must publish GrammaticalInflectionService before AMS reads Settings configuration" >&2
  exit 1
}
grep -A6 -F 't.traceBegin("KikiStartStatusBarManagerService")' "$system_server_src" | \
  grep -Fq 'ServiceManager.addService(Context.STATUS_BAR_SERVICE, kikiStatusBar, false' || {
  echo "Kiki native status bar service is missing from the minimal UI startup" >&2
  exit 1
}
grep -A4 -F 't.traceBegin("KikiStartNotificationManagerService")' "$system_server_src" | \
  grep -Fq 'mSystemServiceManager.startService(NotificationManagerService.class)' || {
  echo "Kiki native notification service is missing from the minimal UI startup" >&2
  exit 1
}
grep -A12 -F 't.traceBegin("KikiStartNotificationManagerService")' "$system_server_src" | \
  grep -Fq 'minimal-notification-channels-skipped' || {
  echo "Kiki minimal notification-channel initialization must tolerate an omitted optional DevicePolicyManagerService" >&2
  exit 1
}
grep -A16 -F 't.traceBegin("KikiStartSystemUI")' "$system_server_src" | \
  grep -Fq 'startSystemUi(context, kikiWindowManager)' || {
  echo "Kiki minimal startup must launch the stock SystemUI service" >&2
  exit 1
}
activity_manager_src="$AOSP_ROOT/frameworks/base/services/core/java/com/android/server/am/ActivityManagerService.java"
grep -A3 -F 'if (phase == PHASE_SYSTEM_SERVICES_READY)' "$activity_manager_src" | \
  grep -Fq 'if (!SystemProperties.getBoolean("ro.kikiaosp.minimal_services", true))' || {
  echo "Kiki minimal profile must skip the network-dependent BatteryStats readiness callback" >&2
  exit 1
}
active_services_src="$AOSP_ROOT/frameworks/base/services/core/java/com/android/server/am/ActiveServices.java"
grep -A5 -F 'void systemServicesReady()' "$active_services_src" | \
  grep -Fq 'if (appStateTracker != null)' || {
  echo "Kiki minimal ActivityManager readiness must tolerate absent DeviceIdleController/AppStateTracker" >&2
  exit 1
}
app_restriction_src="$AOSP_ROOT/frameworks/base/services/core/java/com/android/server/am/AppRestrictionController.java"
grep -A8 -F 'mNotificationHelper.onSystemReady();' "$app_restriction_src" | \
  grep -Fq 'if (appStateTracker != null)' || {
  echo "Kiki minimal ActivityManager readiness must tolerate the intentionally omitted DeviceIdleController/AppStateTracker" >&2
  exit 1
}
grep -A9 -F 'mProcessList.onSystemReady();' "$activity_manager_src" | \
  grep -Fq 'if (!SystemProperties.getBoolean("ro.kikiaosp.minimal_services", true))' || {
  echo "Kiki minimal profile must skip app restriction trackers whose battery/idle dependencies are absent" >&2
  exit 1
}
grep -A10 -F 'IDeviceIdentifiersPolicyService deviceIdentifiers =' "$activity_manager_src" | \
  grep -Fq 'Device identifiers service is unavailable' || {
  echo "Kiki minimal ActivityManager must tolerate the intentionally omitted device identifiers service" >&2
  exit 1
}
proximity_observer_src="$AOSP_ROOT/frameworks/base/services/core/java/com/android/server/display/mode/ProximitySensorObserver.java"
grep -A4 -F 'final SensorManagerInternal sensorManager = mInjector.getSensorManagerInternal();' \
  "$proximity_observer_src" | grep -Fq 'if (sensorManager != null)' || {
  echo "Sensorless Kiki display mode observer must skip an absent SensorManagerInternal" >&2
  exit 1
}
grep -Fq 'android:forceQueryable="true"' \
  "$REPO_ROOT/device/kiki/kikiaosp_test/apps/KikiWindowTest/AndroidManifest.xml" || {
  echo "The optional KikiWindowTest regression APK must be queryable when explicitly installed" >&2
  exit 1
}
init_rc_src="$AOSP_ROOT/system/core/rootdir/init.rc"
grep -Fqx '    init_user0' "$init_rc_src" || {
  echo "AOSP post-fs-data must retain init_user0 to prepare system-user DE storage" >&2
  exit 1
}
grep -Fq 'if (mSupportAutoRotation)' "$AOSP_ROOT/frameworks/base/services/core/java/com/android/server/wm/DisplayRotation.java" && \
grep -Fq 'config_supportAutoRotation">false' \
  "$REPO_ROOT/device/kiki/kikiaosp_test/overlay/frameworks/base/core/res/res/values/config.xml" || {
  echo "Sensorless Kiki device must not initialize the rotation SensorManager" >&2
  exit 1
}
wake_policy_src="$AOSP_ROOT/frameworks/base/services/core/java/com/android/server/policy/PhoneWindowManager.java"
grep -Fq 'SystemProperties.getBoolean("ro.kikiaosp.sensorless", false)' "$wake_policy_src" && \
grep -Fq 'if (mWakeGestureListener == null)' "$wake_policy_src" || {
  echo "Sensorless Kiki device must not initialize the wake-gesture SensorManager" >&2
  exit 1
}
find "$REPO_ROOT/overlays" -type f -printf '%P\n' | sort -u > "$tmp/expected-untracked"
( cd "$AOSP_ROOT"; repo forall -c 'git ls-files --others --exclude-standard | sed "s#^#$REPO_PATH/#"' ) | sed '/^$/d' | sort -u > "$tmp/actual-untracked"
if ! diff -u "$tmp/expected-untracked" "$tmp/actual-untracked"; then echo "AOSP untracked files do not exactly match kikiaosp_test/overlays" >&2; exit 1; fi
if [[ -f "$AOSP_ROOT/out/soong/environment.used" ]]; then
  grep -q '^TARGET_PRODUCT=kikiaosp_test_arm64_phone$' "$AOSP_ROOT/out/soong/environment.used" || { echo "wrong TARGET_PRODUCT" >&2; exit 1; }
  grep -q '^TARGET_BUILD_VARIANT=userdebug$' "$AOSP_ROOT/out/soong/environment.used" || { echo "wrong TARGET_BUILD_VARIANT (must be userdebug)" >&2; exit 1; }
fi
echo "AOSP integration audit: clean and reproducible"
echo "  tracked patch paths: $(wc -l < "$tmp/expected")"
echo "  overlay paths: $(wc -l < "$tmp/expected-untracked")"
echo "  target: kikiaosp_test_arm64_phone / userdebug"
