#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "usage: $0 BASE_STABLE_SYSTEM.img AOSP_ROOT OUTPUT.img [black|surface-test|test-ui]" >&2
    exit 2
fi
base=$(realpath "$1")
aosp_root=$(realpath "$2")
output=$(realpath -m "$3")
mode=${4:-black}
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
device_dir="$repo_dir/device/kiki/kikiaosp_test"
flags="$aosp_root/out/target/product/kikiaosp_test/system/lib64/adbd_flags_c_lib.so"
test_ui="$aosp_root/out/target/product/kikiaosp_test/system/bin/kiki_test_ui"
surfaceflinger="$aosp_root/out/target/product/kikiaosp_test/system/bin/surfaceflinger"
tombstoned="$aosp_root/out/target/product/kikiaosp_test/system/bin/tombstoned"
runtime_apex="$aosp_root/out/target/product/kikiaosp_test/system/apex/com.android.runtime.apex"
crash_dump_policy="$aosp_root/out/target/product/kikiaosp_test/system/etc/seccomp_policy/crash_dump.arm64.policy"
tombstoned_rc="$aosp_root/out/target/product/kikiaosp_test/system/etc/init/tombstoned.rc"
hwc_service="$aosp_root/out/soong/.intermediates/device/generic/goldfish/hals/hwc3/android.hardware.graphics.composer3-service.ranchu/android_vendor_arm64_armv8-a/android.hardware.graphics.composer3-service.ranchu"
framework_lib_dir="$aosp_root/out/target/product/kikiaosp_test/system/lib64"
case "$mode" in
    black) scanout_binary=kiki_black_scanout; scanout_rc=kiki_black_scanout.rc; scanout_variant=black ;;
    # SurfaceFlinger/HWC must own DRM/KMS. Never start the frozen black scanout
    # owner in this mode; it retains DRM master and blocks HWC presentation.
    surface-test) scanout_binary=""; scanout_rc=""; scanout_variant="" ;;
    test-ui) scanout_binary=kiki_test_scanout; scanout_rc=kiki_test_scanout.rc; scanout_variant=test-ui ;;
    *) echo "unknown repack mode: $mode" >&2; exit 2 ;;
esac
if [[ "$base" == "$output" ]]; then
    echo 'output must differ from the frozen base image' >&2
    exit 2
fi
test -f "$flags" || { echo "missing $flags" >&2; exit 2; }
if [[ "$mode" == test-ui ]]; then
    test -f "$device_dir/kiki_test_scanout.rc" || { echo "missing kiki_test_scanout.rc" >&2; exit 2; }
fi
if [[ "$mode" == surface-test ]]; then
    test -f "$test_ui" || { echo "missing $test_ui; build m kiki_test_ui first" >&2; exit 2; }
    test -f "$surfaceflinger" || { echo "missing $surfaceflinger; build m surfaceflinger first" >&2; exit 2; }
    test -f "$tombstoned" || { echo "missing $tombstoned; build m tombstoned first" >&2; exit 2; }
    test -f "$runtime_apex" || { echo "missing $runtime_apex; build the com.android.runtime APEX first" >&2; exit 2; }
    test -f "$crash_dump_policy" || { echo "missing $crash_dump_policy; build m crash_dump first" >&2; exit 2; }
    test -f "$tombstoned_rc" || { echo "missing $tombstoned_rc; build m tombstoned first" >&2; exit 2; }
    test -f "$hwc_service" || { echo "missing $hwc_service; build the active Ranchu HWC service first" >&2; exit 2; }
    test -d "$framework_lib_dir" || { echo "missing matching framework library directory $framework_lib_dir" >&2; exit 2; }
fi
tmp=$(mktemp -d -p "$aosp_root/out" kiki-black.XXXXXX)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/root"
fsck.erofs --extract="$tmp/root" "$base" >"$tmp/extract.log" 2>&1
install -m 0755 "$device_dir/prebuilt/kiki-adbd" "$tmp/root/bin/adbd"
install -m 0755 "$device_dir/kiki-adb-wait.sh" "$tmp/root/bin/kiki-adb-wait.sh"
install -m 0644 "$device_dir/kiki-adb.rc" "$tmp/root/etc/init/kiki-adb.rc"
install -m 0644 "$flags" "$tmp/root/lib64/adbd_flags_c_lib.so"
if [[ -n "$scanout_binary" ]]; then
    if [[ ! -x "$tmp/root/bin/$scanout_binary" ]]; then
        "$repo_dir/scripts/build-black-scanout.sh" "$tmp/root/bin/$scanout_binary" "$scanout_variant"
    fi
    install -m 0644 "$device_dir/$scanout_rc" "$tmp/root/etc/init/$scanout_rc"
fi
if [[ "$mode" == surface-test ]]; then
    # The extracted stable image may already contain the KMS black-screen service.
    # Remove it only from this temporary test image so SF/HWC can take DRM master.
    rm -f "$tmp/root/bin/kiki_black_scanout" \
          "$tmp/root/etc/init/kiki_black_scanout.rc"
    install -D -m 0755 "$surfaceflinger" "$tmp/root/system/bin/surfaceflinger"
    install -m 0755 "$tombstoned" "$tmp/root/system/bin/tombstoned"
    install -D -m 0644 "$runtime_apex" "$tmp/root/system/apex/com.android.runtime.apex"
    install -D -m 0644 "$crash_dump_policy" "$tmp/root/system/etc/seccomp_policy/crash_dump.arm64.policy"
    install -D -m 0644 "$tombstoned_rc" "$tmp/root/system/etc/init/tombstoned.rc"
    # init starts this service via /system/bin/kiki_test_ui. Install through
    # that path so it also works if system/bin is not a symlink to /bin.
    rm -f -- "$tmp/root/bin/kiki_test_ui"
    install -D -m 0755 "$test_ui" "$tmp/root/system/bin/kiki_test_ui"
    cmp "$test_ui" "$tmp/root/system/bin/kiki_test_ui"
    install -m 0644 "$device_dir/kiki_test_ui.rc" "$tmp/root/etc/init/kiki_test_ui.rc"
    # The stable flat image starts HWC directly from /system/bin/hwcomposer;
    # adding an unactivated vendor APEX does not affect the running service.
    install -D -m 0755 "$hwc_service" "$tmp/root/system/bin/hwcomposer"
    # Keep the entire native 64-bit framework library set ABI-coherent with this
    # SurfaceFlinger build. The frozen black base came from an older AOSP tree.
    mkdir -p -- "$tmp/root/system/lib64"
    cp -a "$framework_lib_dir/." "$tmp/root/system/lib64/"
fi
if [[ "$mode" == test-ui ]]; then
    install -m 0644 "$device_dir/kiki_test_scanout.rc" "$tmp/root/etc/init/kiki_test_scanout.rc"
fi

# The frozen flat image was built before the device rename. These partition
# properties feed Android's derived ro.product.* identity and ADB device name.
props="$tmp/root/system_ext/etc/build.prop"
sed -i \
    -e 's/^ro.product.system_ext.brand=.*/ro.product.system_ext.brand=KikiAOSP/' \
    -e 's/^ro.product.system_ext.device=.*/ro.product.system_ext.device=kikiaosp_test/' \
    -e 's/^ro.product.system_ext.manufacturer=.*/ro.product.system_ext.manufacturer=Kiki/' \
    -e 's/^ro.product.system_ext.model=.*/ro.product.system_ext.model=KikiAOSP Test/' \
    "$props"
sed -i '/^debug.sf.kikiaosp_allow_early_composition=/d' "$props"
printf '%s\n' 'debug.sf.kikiaosp_allow_early_composition=true' >> "$props"

mkdir -p -- "$(dirname -- "$output")"
mkfs.erofs -U 6b696b69-414f-5350-7465-737400000001 --all-root \
    -zlz4hc -T 0 "$tmp/system.img" "$tmp/root" >"$tmp/repack.log" 2>&1 || {
    tail -40 "$tmp/repack.log" >&2
    exit 1
}
fsck.erofs "$tmp/system.img" >"$tmp/check.log" 2>&1 || {
    tail -40 "$tmp/check.log" >&2
    exit 1
}
mv -- "$tmp/system.img" "$output"
sha256sum "$output"
