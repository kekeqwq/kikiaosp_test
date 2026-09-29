#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd -- "$script_dir/.." && pwd)
kiki_minimal_native_rc="$project_root/device/kiki/kikiaosp_test/kiki-minimal-native.rc"

if [[ $# -ne 4 ]]; then
    echo "usage: $0 BASE_STABLE_SYSTEM.img AOSP_ROOT KikiWindowTest.apk OUTPUT.img" >&2
    exit 2
fi

base=$(realpath "$1")
aosp_root=$(realpath "$2")
apk=$(realpath "$3")
output=$(realpath -m "$4")
product="$aosp_root/out/target/product/kikiaosp_test"
system_tree="$product/system"
vendor_tree="$product/vendor"
product_tree="$system_tree/product"
system_ext_tree="$system_tree/system_ext"
deapexer="$aosp_root/out/host/linux-x86/bin/deapexer"
mkfs_erofs="$aosp_root/out/host/linux-x86/bin/mkfs.erofs"
file_contexts="$product/obj/ETC/file_contexts.bin_intermediates/file_contexts.bin"

[[ -f "$base" ]] || { echo "missing frozen base: $base" >&2; exit 2; }
[[ -f "$aosp_root/.repo/manifest.xml" ]] || { echo "not an AOSP checkout: $aosp_root" >&2; exit 2; }
[[ -f "$apk" ]] || { echo "missing APK: $apk" >&2; exit 2; }
[[ -f "$kiki_minimal_native_rc" ]] || { echo "missing Kiki minimal init policy: $kiki_minimal_native_rc" >&2; exit 2; }
[[ -x "$deapexer" ]] || { echo "missing AOSP deapexer: $deapexer" >&2; exit 2; }
[[ -x "$mkfs_erofs" ]] || { echo "missing AOSP mkfs.erofs: $mkfs_erofs" >&2; exit 2; }
[[ -f "$file_contexts" ]] || { echo "missing built SELinux file contexts: $file_contexts" >&2; exit 2; }
[[ -d "$system_tree" && -d "$vendor_tree" && -d "$product_tree" && -d "$system_ext_tree" ]] || {
    echo "missing built system/vendor/product/system_ext trees under $product" >&2
    exit 2
}
[[ -x "$system_tree/bin/init" && -x "$system_tree/bin/app_process64" && -f "$system_tree/framework/services.jar" && -f "$system_tree/etc/init/hw/init.zygote64.rc" ]] || {
    echo "Android init/runtime payload is incomplete in $system_tree" >&2
    exit 2
}
[[ -f "$system_tree/bin/kiki-adbd" && -f "$system_tree/lib64/adbd_flags_c_lib.so" ]] || {
    echo "matching Kiki ADB payload is missing from $system_tree" >&2
    exit 2
}
[[ "$base" != "$output" ]] || { echo "output must differ from the frozen base image" >&2; exit 2; }
[[ "$output" == *.img ]] || { echo "output must end in .img" >&2; exit 2; }
output_dir=$(dirname -- "$output")
output_stem=$(basename -- "$output" .img)
vendor_output="$output_dir/$output_stem-vendor.img"
product_output="$output_dir/$output_stem-product.img"
system_ext_output="$output_dir/$output_stem-system_ext.img"
[[ ! -e "$output" && ! -e "$vendor_output" && ! -e "$product_output" && ! -e "$system_ext_output" ]] || {
    echo "refusing to overwrite existing test image output" >&2
    exit 2
}

tmp=$(mktemp -d -p "$aosp_root/out" kiki-apk-window.XXXXXX)
case "$tmp" in
    "$aosp_root"/out/kiki-apk-window.*) ;;
    *) echo "temporary extraction escaped AOSP out/: $tmp" >&2; exit 2 ;;
esac
cleanup_tmp() {
    # EROFS extraction preserves read-only directory modes; make only the
    # generated temporary tree removable before cleaning it up.
    find "$tmp" -type d -exec chmod u+rwx {} + 2>/dev/null || true
    rm -rf -- "$tmp"
}
trap cleanup_tmp EXIT
mkdir -p "$tmp/root"
fsck.erofs --extract="$tmp/root" "$base" >"$tmp/extract.log" 2>&1

# Keep the complete bootable root from the frozen image. The known-good Android
# init, linker/APEX runtime, linker config, vendor graphics stack, and init
# support files are a coupled baseline; replacing the root with a new product
# tree makes the first-stage handoff fail before init reaches main().
base_system="$tmp/root/system"
base_egl="$tmp/root/vendor/lib64/egl"
base_graphics_rc="$tmp/root/vendor/etc/init/init_graphics.vendor.rc"
base_allocator="$tmp/root/system_ext/bin/hw/android.hidl.allocator@1.0-service"
base_allocator_rc="$tmp/root/system_ext/etc/init/android.hidl.allocator@1.0-service.rc"
base_composer="$tmp/root/apex/com.android.hardware.graphics.composer/bin/hw/android.hardware.graphics.composer3-service.ranchu"
[[ -d "$base_system" && ! -L "$base_system" && -d "$base_egl" && -f "$base_graphics_rc" && -x "$base_allocator" && -f "$base_allocator_rc" && -f "$base_composer" && -f "$tmp/root/linkerconfig/ld.config.txt" && -x "$tmp/root/bin/init" && -x "$tmp/root/bin/bootstrap/linker64" ]] || {
    echo "frozen base is missing its tested display or early-boot support files" >&2
    exit 2
}

# The frozen image's /bin/init predates the APEX mount-namespace fix. Carry the
# freshly built Android init binary into the root image; replacing only the
# /system tree would otherwise leave the failing init executable in place.
install -D -m 0750 "$system_tree/bin/init" "$tmp/root/bin/init"
cmp -s "$system_tree/bin/init" "$tmp/root/bin/init" || {
    echo "failed to stage the freshly built init binary into the boot root" >&2
    exit 2
}

# Overlay the Android 17 system tree at its proven /system handoff point while
# retaining every other path from the stable image. Its /vendor symlink must
# continue to resolve to the frozen, working guest graphics stack.
case "$base_system" in
    "$aosp_root"/out/kiki-apk-window.*/root/system) ;;
    *) echo "refusing unsafe base system path: $base_system" >&2; exit 2 ;;
esac
base_policy_mapping="$tmp/base-policy-mapping"
[[ -d "$base_system/etc/selinux/mapping" ]] || {
    echo "frozen base is missing its tested SELinux mapping directory" >&2
    exit 2
}
mkdir -p "$base_policy_mapping"
cp -a "$base_system/etc/selinux/mapping/." "$base_policy_mapping/"
rm -rf -- "$base_system"
mkdir -p "$base_system"
cp -a "$system_tree/." "$base_system/"
# A target-only incremental build may leave a newer vendor sepolicy version
# without the corresponding mapping staged in the system tree. Preserve any
# missing compatibility maps from the known-good frozen base; don't overwrite
# maps that the current AOSP system tree did build.
mkdir -p "$base_system/etc/selinux/mapping"
cp -an "$base_policy_mapping/." "$base_system/etc/selinux/mapping/"
install -D -m 0644 "$kiki_minimal_native_rc" "$base_system/etc/init/kiki-minimal-native.rc"
grep -Fqx '    export ANDROID_DATA /data' "$base_system/etc/init/kiki-minimal-native.rc" || {
    echo "Kiki init policy does not export ANDROID_DATA for class-main services" >&2
    exit 2
}
[[ -L "$base_system/vendor" && "$(readlink "$base_system/vendor")" == "/vendor" ]] || {
    echo "unexpected Android 17 system-tree vendor entry" >&2
    exit 2
}

# This diagnostic image exercises the single mount-namespace path to avoid
# PID 1 unsharing fs_struct while its property-service threads still use it.
# The canonical product property is also in the device makefile; inject it
# here because this repack intentionally reuses a frozen system tree.
system_build_prop="$base_system/build.prop"
[[ -f "$system_build_prop" ]] || { echo "missing system build properties: $system_build_prop" >&2; exit 2; }
sed -i '/^ro.kikiaosp.single_mount_namespace=/d' "$system_build_prop"
printf '\nro.kikiaosp.single_mount_namespace=true\n' >> "$system_build_prop"
grep -Fqx 'ro.kikiaosp.single_mount_namespace=true' "$system_build_prop"
# The fixed-orientation Kiki overlay is required before WindowManagerService
# construction; the minimal profile otherwise skips OverlayManagerService.
sed -i '/^ro.kikiaosp.overlay_manager=/d' "$system_build_prop"
printf 'ro.kikiaosp.overlay_manager=true\n' >> "$system_build_prop"
grep -Fqx 'ro.kikiaosp.overlay_manager=true' "$system_build_prop"
sed -i '/^ro.kikiaosp.sensorless=/d' "$system_build_prop"
printf 'ro.kikiaosp.sensorless=true\n' >> "$system_build_prop"
grep -Fqx 'ro.kikiaosp.sensorless=true' "$system_build_prop"
sed -i '/^ro.kikiaosp.sensor_privacy=/d' "$system_build_prop"
printf 'ro.kikiaosp.sensor_privacy=true\n' >> "$system_build_prop"
grep -Fqx 'ro.kikiaosp.sensor_privacy=true' "$system_build_prop"
sed -i '/^ro.kikiaosp.role_manager=/d' "$system_build_prop"
printf 'ro.kikiaosp.role_manager=true\n' >> "$system_build_prop"
grep -Fqx 'ro.kikiaosp.role_manager=true' "$system_build_prop"
sed -i '/^ro.kikiaosp.usage_stats=/d' "$system_build_prop"
printf 'ro.kikiaosp.usage_stats=true\n' >> "$system_build_prop"
grep -Fqx 'ro.kikiaosp.usage_stats=true' "$system_build_prop"
# Skip SurfaceFlinger's one-time shader prewarm: minigbm cannot allocate its
# offscreen DRM dumb buffers on this virtio-gpu path. This does not disable
# RenderEngine composition for actual app/display frames.
sed -i '/^debug\.sf\.prime_shader_cache\.hole_punch=/d; /^service\.sf\.prime_shader_cache=/d' "$system_build_prop"
printf 'service.sf.prime_shader_cache=false\n' >> "$system_build_prop"
grep -Fqx 'service.sf.prime_shader_cache=false' "$system_build_prop"

# FirstStageMount switches root to the /system partition before mounting the
# remaining fstab entries. Ensure required paths therefore exist inside this
# root image (initramfs copies alone are no longer visible). In particular,
# init creates /apex and /bootstrap-apex mount namespaces before parsing init.rc.
# Zygote's native forkSystemServer bind-mounts /mnt/user/0 onto /storage.
mkdir -p "$tmp/root/data" "$tmp/root/metadata" "$tmp/root/storage" \
    "$tmp/root/apex" "$tmp/root/bootstrap-apex"
chmod 0755 "$tmp/root/storage"

# The classpath helper is supplied by the SDKExt APEX. Keep zygote blocked until
# APEX activation and classpath derivation have completed; late-init queues the
# zygote-start trigger independently of the post-fs-data action. Do not let the
# device's diagnostic static SYSTEMSERVERCLASSPATH replace Android's generated
# APEX-aware classpath.
android_init_rc="$base_system/etc/init/hw/init.rc"
[[ -f "$android_init_rc" ]] || { echo "missing Android init.rc: $android_init_rc" >&2; exit 2; }
if ! grep -A1 -F 'setprop vold.decrypt trigger_restart_framework' "$android_init_rc" | grep -Fq 'trigger nonencrypted'; then
    awk '
        index($0, "setprop vold.decrypt trigger_restart_framework") && !inserted {
            print
            print "    trigger nonencrypted"
            inserted = 1
            next
        }
        { print }
        END { if (!inserted) exit 1 }
    ' "$android_init_rc" > "$android_init_rc.new"
    mv -- "$android_init_rc.new" "$android_init_rc"
fi
grep -A1 -F 'setprop vold.decrypt trigger_restart_framework' "$android_init_rc" | grep -Fq 'trigger nonencrypted' || {
    echo "failed to trigger Android nonencrypted class-start action" >&2
    exit 2
}
grep -Fq 'on nonencrypted' "$android_init_rc" || {
    echo "Android init.rc has no nonencrypted framework-start action" >&2
    exit 2
}
zygote_init_rc="$base_system/etc/init/hw/init.zygote64.rc"
[[ -f "$zygote_init_rc" ]] || { echo "missing 64-bit zygote init rc: $zygote_init_rc" >&2; exit 2; }
# Do not let the bootstrap-only early-init path predeclare full APEX activation.
# The post-fs-data wait must observe the main apexd activation after all
# framework classpath fragments have been mounted.
sed -i '/^[[:space:]]*setprop apexd\.status activated[[:space:]]*$/d' "$android_init_rc"
if grep -Fq 'setprop apexd.status activated' "$android_init_rc"; then
    echo "refusing to boot with a synthetic early apexd.status=activated" >&2
    exit 2
fi
sed -i '/^[[:space:]]*setenv SYSTEMSERVERCLASSPATH[[:space:]]/d' "$zygote_init_rc"
if grep -q 'setenv SYSTEMSERVERCLASSPATH' "$zygote_init_rc"; then
    echo "refusing to boot with a static SYSTEMSERVERCLASSPATH override" >&2
    exit 2
fi
sed -i '/^[[:space:]]*setprop kikiaosp\.ignore_apex_versions 1[[:space:]]*$/d' "$zygote_init_rc"
if grep -q 'setprop kikiaosp\.ignore_apex_versions' "$zygote_init_rc"; then
    echo "refusing to keep a property command in the zygote service stanza" >&2
    exit 2
fi
if ! grep -q '^[[:space:]]*setprop kikiaosp\.ignore_apex_versions 1[[:space:]]*$' "$android_init_rc"; then
    awk '
        /^on early-init([[:space:]]|$)/ && !inserted {
            print
            print "    setprop kikiaosp.ignore_apex_versions 1"
            inserted = 1
            next
        }
        { print }
        END { if (!inserted) exit 1 }
    ' "$android_init_rc" > "$android_init_rc.new"
    mv -- "$android_init_rc.new" "$android_init_rc"
fi
grep -q '^[[:space:]]*setprop kikiaosp\.ignore_apex_versions 1[[:space:]]*$' "$android_init_rc"
# The stable image can contain an older injected rule. Always remove it: the
# generated linkerconfig must retain the APEX namespaces for this Android build.
sed -i '\|^[[:space:]]*copy /system/etc/ld\.config\.kiki\.txt /linkerconfig/ld\.config\.txt[[:space:]]*$|d' "$android_init_rc"
if ! grep -Fq 'setprop kikiaosp.classpath.ready 1' "$android_init_rc"; then
    awk '
        /exec_start derive_classpath/ && !inserted_wait {
            print "    setprop dalvik.vm.heapgrowthlimit 256m"
            print "    setprop dalvik.vm.heapsize 512m"
            print "    wait_for_prop apexd.status activated"
            inserted_wait = 1
        }
        /load_exports \/data\/system\/environ\/classpath/ && !inserted_ready {
            print
            print "    setprop kikiaosp.classpath.ready 1"
            inserted_ready = 1
            next
        }
        { print }
        END { if (!inserted_wait || !inserted_ready) exit 1 }
    ' "$android_init_rc" > "$android_init_rc.new"
    mv -- "$android_init_rc.new" "$android_init_rc"
fi
grep -B1 -F 'exec_start derive_classpath' "$android_init_rc" | grep -q 'wait_for_prop apexd.status activated'
grep -B3 -F 'exec_start derive_classpath' "$android_init_rc" | grep -q 'setprop dalvik.vm.heapgrowthlimit 256m'
grep -B3 -F 'exec_start derive_classpath' "$android_init_rc" | grep -q 'setprop dalvik.vm.heapsize 512m'
grep -A1 -F 'load_exports /data/system/environ/classpath' "$android_init_rc" | grep -q 'setprop kikiaosp.classpath.ready 1'
if ! grep -Fq 'wait_for_prop kikiaosp.classpath.ready 1' "$android_init_rc"; then
    awk '
        /^on zygote-start([[:space:]]|$)/ && !inserted {
            print
            print "    wait_for_prop kikiaosp.classpath.ready 1"
            inserted = 1
            next
        }
        { print }
        END { if (!inserted) exit 1 }
    ' "$android_init_rc" > "$android_init_rc.new"
    mv -- "$android_init_rc.new" "$android_init_rc"
fi
grep -A2 -E '^on zygote-start([[:space:]]|$)' "$android_init_rc" | grep -q 'wait_for_prop kikiaosp.classpath.ready 1'
! grep -Fq 'copy /system/etc/ld.config.kiki.txt /linkerconfig/ld.config.txt' "$android_init_rc"

# In this stripped boot path, non-bootstrap APEX init rc files are not imported
# automatically. Register the two services that init.rc explicitly starts.
sdkext_classpath_rc="$product/apex/com.android.sdkext/etc/derive_classpath.rc"
art_apex_init_rc="$product/apex/com.android.art/etc/init.rc"
[[ -f "$sdkext_classpath_rc" && -f "$art_apex_init_rc" ]] || {
    echo "missing APEX init definitions for classpath/ART boot" >&2
    exit 2
}
install -D -m 0644 "$sdkext_classpath_rc" "$base_system/etc/init/derive_classpath.rc"
install -D -m 0644 "$art_apex_init_rc" "$base_system/etc/init/kiki-art-apex.rc"

# Zygote repeatedly aborts at the same late entry while preloading the full
# phone class list. Preloading is a startup optimization, not required to run
# this single APK Activity; let ART resolve classes on demand in this test.
preloaded_classes="$base_system/etc/preloaded-classes"
[[ -f "$preloaded_classes" ]] || { echo "missing preloaded-classes: $preloaded_classes" >&2; exit 2; }
: > "$preloaded_classes"

# Remove the stale default-namespace copy from the frozen root. Android 17's
# i18n APEX is the sole libicu provider in this test image.
rm -f "$tmp/root/lib64/libicu.so"
[[ ! -e "$base_system/lib64/libicu.so" && ! -L "$base_system/lib64/libicu.so" ]] || {
    echo "unexpected default-namespace libicu.so in the Android 17 system tree" >&2
    exit 2
}

# Use the Android 17 runtime APEXes as the sole provider for these libraries.
# The device tree's legacy prebuilts duplicated APEX contents in the default
# linker namespace and made linkerconfig abort before zygote startup.
apex_runtime_libs=(
    libnativeloader.so libsigchain.so libicu.so libnativebridge.so libicuuc.so
    libicui18n.so libandroidicu.so libnativehelper.so libart.so libartbase.so
    libartpalette.so libdexfile.so libprofile.so libstatspull.so libstatssocket.so
    libcom.android.tethering.connectivity_native.so libicu_jni.so libjavacore.so
    libopenjdk.so libopenjdkjvm.so libandroidio.so
)
for library in "${apex_runtime_libs[@]}"; do
    rm -f "$base_system/lib64/$library" "$base_system/lib64/bootstrap/$library"
done

# Install the matching no-auth TCP ADB daemon and native-window APK into the
# current Android 17 /system tree.
install -D -m 0755 "$system_tree/bin/kiki-adbd" "$base_system/bin/adbd"
install -D -m 0644 "$system_tree/lib64/adbd_flags_c_lib.so" "$base_system/lib64/adbd_flags_c_lib.so"
install -D -m 0644 "$apk" "$base_system/app/KikiWindowTest/KikiWindowTest.apk"

# The Activity replaces the earlier init-launched SurfaceComposer test layer.
rm -f "$tmp/root/etc/init/kiki_test_ui.rc" \
      "$base_system/etc/init/kiki_test_ui.rc" \
      "$tmp/root/etc/init/kiki_black_scanout.rc" \
      "$base_system/etc/init/kiki_black_scanout.rc" \
      "$tmp/root/bin/kiki_test_ui" \
      "$tmp/root/bin/kiki_black_scanout" \
      "$base_system/bin/kiki_test_ui" \
      "$base_system/bin/kiki_black_scanout"

# Build Android's normal independent partitions in the device-tree fstab order.
# Keep the known-good guest HWC files while using the new vendor property set
# (including ro.zygote=zygote64) from the current Android 17 build.
mkdir -p "$tmp/vendor" "$tmp/product" "$tmp/system_ext"
cp -a "$vendor_tree/." "$tmp/vendor/"
vendor_sepolicy_version_file="$tmp/vendor/etc/selinux/plat_sepolicy_vers.txt"
vendor_genfs_version_file="$tmp/vendor/etc/selinux/genfs_labels_version.txt"
[[ -f "$vendor_sepolicy_version_file" && -f "$vendor_genfs_version_file" ]] || {
    echo "vendor SELinux policy version metadata is missing" >&2
    exit 2
}
vendor_sepolicy_version=$(tr -d '[:space:]' < "$vendor_sepolicy_version_file")
vendor_genfs_version=$(tr -d '[:space:]' < "$vendor_genfs_version_file")
[[ -n "$vendor_sepolicy_version" && "$vendor_sepolicy_version" != */* ]] || {
    echo "invalid vendor SELinux policy version: $vendor_sepolicy_version" >&2
    exit 2
}
[[ -n "$vendor_genfs_version" && "$vendor_genfs_version" != */* ]] || {
    echo "invalid vendor genfs labels version: $vendor_genfs_version" >&2
    exit 2
}
[[ -f "$base_system/etc/selinux/mapping/$vendor_sepolicy_version.cil" ]] || {
    echo "system policy mapping is missing for vendor sepolicy version $vendor_sepolicy_version" >&2
    exit 2
}
[[ -f "$base_system/etc/selinux/plat_sepolicy_genfs_$vendor_genfs_version.cil" ]] || {
    echo "system genfs policy is missing for vendor genfs labels version $vendor_genfs_version" >&2
    exit 2
}
mkdir -p "$tmp/vendor/lib64"
rm -rf -- "$tmp/vendor/lib64/egl"
cp -a "$base_egl" "$tmp/vendor/lib64/egl"
install -D -m 0644 "$base_graphics_rc" "$tmp/vendor/etc/init/init_graphics.vendor.rc"
# The minimal Ranchu init rc invokes mount_all on /vendor/etc/fstab.ranchu.
# Keep these paired device-tree files together in the vendor image even when
# the current product output predates the copy-file destination correction.
fstab_ranchu="$vendor_tree/etc/fstab.ranchu"
if [[ ! -f "$fstab_ranchu" ]]; then
    fstab_ranchu="$aosp_root/device/kiki/kikiaosp_test/fstab.ranchu"
fi
[[ -f "$fstab_ranchu" ]] || { echo "missing ranchu fstab: $fstab_ranchu" >&2; exit 2; }
install -D -m 0644 "$fstab_ranchu" "$tmp/vendor/etc/fstab.ranchu"
ranchu_init_rc="$aosp_root/device/kiki/kikiaosp_test/init.ranchu.rc"
[[ -f "$ranchu_init_rc" ]] || { echo "missing minimal ranchu init rc: $ranchu_init_rc" >&2; exit 2; }
install -D -m 0644 "$ranchu_init_rc" "$tmp/vendor/etc/init/hw/init.ranchu.rc"
cp -a "$product_tree/." "$tmp/product/"
cp -a "$system_ext_tree/." "$tmp/system_ext/"
install -D -m 0755 "$base_allocator" "$tmp/system_ext/bin/hw/android.hidl.allocator@1.0-service"
install -D -m 0644 "$base_allocator_rc" "$tmp/system_ext/etc/init/android.hidl.allocator@1.0-service.rc"

# SurfaceFlinger in this minimal device runs in the system linker namespace,
# which currently cannot resolve the vendor Vulkan APEX namespace. Use the
# same AOSP Pastel driver as a normal SPHAL module instead, and provide the
# standard minigbm AIDL allocator/mapper pair expected by the Ranchu HWC3 HAL.
allocator_module="$aosp_root/out/soong/.intermediates/external/minigbm/cros_gralloc/aidl/android.hardware.graphics.allocator-service.minigbm"
mapper_module="$aosp_root/out/soong/.intermediates/external/minigbm/cros_gralloc/mapper_stablec/mapper.minigbm"
vulkan_module="$aosp_root/out/soong/.intermediates/external/swiftshader/src/vulkan.pastel"
libhardware_module="$aosp_root/out/soong/.intermediates/hardware/libhardware/libhardware"
allocator_bin="$allocator_module/android_vendor_arm64_armv8-a_cortex-a53_apex10000/android.hardware.graphics.allocator-service.minigbm"
mapper_lib="$mapper_module/android_vendor_arm64_armv8-a_cortex-a53_shared_apex10000/mapper.minigbm.so"
vulkan_lib="$vulkan_module/android_vendor_arm64_armv8-a_cortex-a53_shared_apex10000/vulkan.pastel.so"
dmabufheap_lib="$system_tree/lib64/libdmabufheap.so"
libhardware_lib="$libhardware_module/android_vendor_arm64_armv8-a_cortex-a53_shared/libhardware.so"
[[ -n "$allocator_bin" && -f "$allocator_bin" ]] || { echo "missing built minigbm allocator: $allocator_module" >&2; exit 2; }
[[ -n "$mapper_lib" && -f "$mapper_lib" ]] || { echo "missing built minigbm mapper: $mapper_module" >&2; exit 2; }
[[ -n "$vulkan_lib" && -f "$vulkan_lib" ]] || { echo "missing built Pastel Vulkan HAL: $vulkan_module" >&2; exit 2; }
[[ -n "$dmabufheap_lib" && -f "$dmabufheap_lib" ]] || { echo "missing built libdmabufheap: $dmabufheap_lib" >&2; exit 2; }
[[ -n "$libhardware_lib" && -f "$libhardware_lib" ]] || { echo "missing built libhardware: $libhardware_module" >&2; exit 2; }
[[ -f "$aosp_root/external/minigbm/cros_gralloc/aidl/allocator.rc" && \
   -f "$aosp_root/external/minigbm/cros_gralloc/aidl/allocator.xml" ]] || {
    echo "missing AOSP minigbm allocator init/VINTF files" >&2
    exit 2
}

# Do not activate the Vulkan APEX for this image: its RC sets ro.vulkan.apex,
# but its namespace is absent from the system process linker config.
rm -f "$tmp/vendor/apex/com.google.cf.vulkan.apex"
rm -f "$tmp/vendor/bin/hw/kiki-allocator-system" \
      "$tmp/vendor/lib64/hw/kiki-mapper-minigbm.so"
install -D -m 0755 "$allocator_bin" \
    "$tmp/vendor/bin/hw/android.hardware.graphics.allocator-service.minigbm"
install -D -m 0644 "$aosp_root/external/minigbm/cros_gralloc/aidl/allocator.rc" \
    "$tmp/vendor/etc/init/allocator.minigbm.rc"
if ! grep -q 'IAllocator/default' "$tmp/vendor/etc/vintf/manifest.xml" 2>/dev/null && \
   ! grep -R -q 'IAllocator/default' "$tmp/vendor/etc/vintf/manifest" 2>/dev/null; then
    install -D -m 0644 "$aosp_root/external/minigbm/cros_gralloc/aidl/allocator.xml" \
        "$tmp/vendor/etc/vintf/manifest/android.hardware.graphics.allocator-service.minigbm.xml"
fi
install -D -m 0644 "$mapper_lib" "$tmp/vendor/lib64/hw/mapper.minigbm.so"
install -D -m 0644 "$vulkan_lib" "$tmp/vendor/lib64/hw/vulkan.pastel.so"
# GraphicBufferMapper resolves this module specifically from /system_ext.
install -D -m 0644 "$mapper_lib" "$tmp/root/system_ext/lib64/hw/mapper.minigbm.so"
install -D -m 0644 "$mapper_lib" "$tmp/system_ext/lib64/hw/mapper.minigbm.so"
# Expose the mapper dependency in vendor's default search path as well as the
# normal system paths; the Ranchu composer service falls back to its current
# linker namespace when the SPHAL namespace is unavailable.
# This QEMU fstab mounts the full root image at /system and does not mount the
# separate system_ext virtio disk; place it in both trees for either layout.
install -D -m 0644 "$dmabufheap_lib" "$tmp/root/system_ext/lib64/libdmabufheap.so"
install -D -m 0644 "$dmabufheap_lib" "$tmp/system_ext/lib64/libdmabufheap.so"
install -D -m 0644 "$dmabufheap_lib" "$base_system/lib64/libdmabufheap.so"
install -D -m 0644 "$dmabufheap_lib" "$base_system/lib64/bootstrap/libdmabufheap.so"
install -D -m 0644 "$dmabufheap_lib" "$tmp/vendor/lib64/libdmabufheap.so"
# Pastel is loaded from the SPHAL namespace, whose search paths include vendor.
install -D -m 0644 "$libhardware_lib" "$tmp/vendor/lib64/libhardware.so"

# This test boot has no usable SELinux file-context database on writable data,
# so apexd cannot restorecon the payload extracted from CAPEX and refuses to
# activate those APEXes. Expand CAPEX to regular APEX files in the temporary
# images; the source product trees remain untouched.
shopt -s nullglob
for apex_dir in "$base_system/apex" "$tmp/vendor/apex" "$tmp/product/apex" "$tmp/system_ext/apex"; do
    [[ -d "$apex_dir" ]] || continue
    for capex in "$apex_dir"/*.capex; do
        [[ -f "$capex" ]] || continue
        apex="${capex%.capex}.apex"
        "$deapexer" decompress --input "$capex" --output "$apex"
        rm -- "$capex"
    done
done
shopt -u nullglob

# Stage only the required, matching AOSP-built runtime libraries into /system's
# normal search directory so early zygote/media processes can resolve them.
apex_payload="$tmp/apex-payload"
mkdir -p "$apex_payload"
for apex_name in com.android.art com.android.i18n com.android.os.statsd com.android.tethering; do
    apex_file="$base_system/apex/$apex_name.apex"
    [[ -f "$apex_file" ]] || { echo "missing regular APEX payload: $apex_file" >&2; exit 2; }
    apex_extract="$apex_payload/$apex_name"
    mkdir -p "$apex_extract"
    ANDROID_HOST_OUT="$aosp_root/out/host/linux-x86" \
        "$deapexer" extract "$apex_file" "$apex_extract"
done
copy_apex_library() {
    local apex_name="$1" library="$2" source="$apex_payload/$1/lib64/$2"
    [[ -f "$source" ]] || { echo "missing APEX library: $source" >&2; exit 2; }
    install -D -m 0644 "$source" "$base_system/lib64/$library"
}
# Keep libart.so in its owning ART APEX. A second copy in /system/lib64 makes
# the default namespace initialize one Runtime singleton while ART-namespace
# libopenjdkjvm resolves its own libart.so from the APEX; JVM_NativeLoad then
# dereferences a null Runtime::Current() during StatsLog's native load.
for library in libnativeloader.so libsigchain.so libnativebridge.so libnativehelper.so \
               libartbase.so libartpalette.so libdexfile.so libprofile.so \
               libjavacore.so libopenjdk.so libopenjdkjvm.so libandroidio.so; do
    copy_apex_library com.android.art "$library"
done
# ART hardcodes /system/lib64/libicu_jni.so. The Kiki linker config below
# exports its matching ICU dependencies from the i18n APEX namespace.
for library in libicu.so libicuuc.so libicui18n.so libandroidicu.so libicu_jni.so; do
    copy_apex_library com.android.i18n "$library"
done
for library in libstatspull.so libstatssocket.so; do
    copy_apex_library com.android.os.statsd "$library"
done
copy_apex_library com.android.tethering libcom.android.tethering.connectivity_native.so

allocator_manifest_count=0
if [[ -f "$tmp/vendor/etc/vintf/manifest.xml" ]]; then
    allocator_manifest_count=$(grep -c 'IAllocator/default' "$tmp/vendor/etc/vintf/manifest.xml" || true)
fi
allocator_fragment_count=$({ grep -R -h -c 'IAllocator/default' "$tmp/vendor/etc/vintf/manifest" 2>/dev/null || true; } |
    awk '{sum += $1} END {print sum + 0}')
allocator_declaration_count=$((allocator_manifest_count + allocator_fragment_count))
[[ -f "$tmp/vendor/bin/hw/android.hardware.graphics.allocator-service.minigbm" && \
   "$allocator_declaration_count" -eq 1 && \
   -f "$tmp/vendor/lib64/hw/mapper.minigbm.so" && \
   -f "$tmp/root/system_ext/lib64/hw/mapper.minigbm.so" && \
   -f "$tmp/system_ext/lib64/hw/mapper.minigbm.so" && \
   -f "$tmp/vendor/lib64/hw/vulkan.pastel.so" && \
   -f "$tmp/root/system_ext/lib64/libdmabufheap.so" && \
   -f "$tmp/system_ext/lib64/libdmabufheap.so" && \
   -f "$base_system/lib64/libdmabufheap.so" && \
   -f "$tmp/vendor/lib64/libdmabufheap.so" && \
   -f "$tmp/vendor/lib64/libhardware.so" && \
   ! -e "$tmp/vendor/bin/hw/kiki-allocator-system" && \
   ! -e "$tmp/vendor/lib64/hw/kiki-mapper-minigbm.so" && \
   ! -e "$tmp/vendor/apex/com.google.cf.vulkan.apex" ]] || {
    echo "minigbm/Pastel vendor graphics overlay is incomplete" >&2
    exit 2
}

mkdir -p "$(dirname -- "$output")"
# Let AOSP fs_config supply Android ownership, execute bits, and capabilities;
# forcing all files to root breaks services such as logd (root:logd 0550).
"$mkfs_erofs" --file-contexts="$file_contexts" --mount-point=/ \
    --product-out="$product" -U 6b696b69-414f-5350-7465-737400000001 \
    -zlz4hc -T 0 "$tmp/system.img" "$tmp/root" >"$tmp/repack.log" 2>&1 || {
    tail -40 "$tmp/repack.log" >&2
    exit 1
}
fsck.erofs "$tmp/system.img" >"$tmp/check.log" 2>&1 || {
    tail -40 "$tmp/check.log" >&2
    exit 1
}
for partition in vendor product system_ext; do
    case "$partition" in
        vendor) uuid=6b696b69-414f-5350-7465-737400000002 ;;
        product) uuid=6b696b69-414f-5350-7465-737400000003 ;;
        system_ext) uuid=6b696b69-414f-5350-7465-737400000004 ;;
    esac
    "$mkfs_erofs" --file-contexts="$file_contexts" --mount-point="/$partition" \
        --product-out="$product" -U "$uuid" \
        -zlz4hc -T 0 "$tmp/$partition.img" "$tmp/$partition" >"$tmp/$partition.log" 2>&1 || {
        tail -40 "$tmp/$partition.log" >&2
        exit 1
    }
    fsck.erofs "$tmp/$partition.img" >"$tmp/$partition.check.log" 2>&1 || {
        tail -40 "$tmp/$partition.check.log" >&2
        exit 1
    }
done
mv -- "$tmp/system.img" "$output"
mv -- "$tmp/vendor.img" "$vendor_output"
mv -- "$tmp/product.img" "$product_output"
mv -- "$tmp/system_ext.img" "$system_ext_output"
sha256sum "$output" "$vendor_output" "$product_output" "$system_ext_output"
