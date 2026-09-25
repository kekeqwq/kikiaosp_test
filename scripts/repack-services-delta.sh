#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 BASE_SYSTEM.img AOSP_ROOT OUTPUT_SYSTEM.img" >&2
    exit 2
fi

base=$(realpath "$1")
aosp_root=$(realpath "$2")
output=$(realpath -m "$3")
product="$aosp_root/out/target/product/kikiaosp_test"
services_jar="$product/system/framework/services.jar"
services_prof="$product/system/framework/services.jar.prof"
services_oat="$product/system/framework/oat/arm64"
file_contexts="$product/obj/ETC/file_contexts.bin_intermediates/file_contexts.bin"
mkfs_erofs="$aosp_root/out/host/linux-x86/bin/mkfs.erofs"

[[ -f "$base" ]] || { echo "missing frozen base image: $base" >&2; exit 2; }
[[ -f "$aosp_root/.repo/manifest.xml" ]] || { echo "not an AOSP checkout: $aosp_root" >&2; exit 2; }
[[ -f "$services_jar" && -f "$services_prof" && -f "$services_oat/services.odex" && \
   -f "$services_oat/services.vdex" && -f "$services_oat/services.art" ]] || {
    echo "matching built services.jar/ART artifacts are incomplete" >&2
    exit 2
}
[[ -f "$file_contexts" && -x "$mkfs_erofs" ]] || {
    echo "missing EROFS tool or Android file-context database" >&2
    exit 2
}
[[ "$output" == "$aosp_root"/out/*.img && "$output" != "$base" ]] || {
    echo "output must be a new image under AOSP out/ and differ from the frozen base" >&2
    exit 2
}
[[ ! -e "$output" ]] || { echo "refusing to overwrite image: $output" >&2; exit 2; }

base_stem=${base%.img}
output_stem=${output%.img}
for partition in vendor product system_ext; do
    [[ -f "$base_stem-$partition.img" ]] || {
        echo "missing frozen $partition sidecar: $base_stem-$partition.img" >&2
        exit 2
    }
    [[ ! -e "$output_stem-$partition.img" ]] || {
        echo "refusing to overwrite sidecar: $output_stem-$partition.img" >&2
        exit 2
    }
done

tmp=$(mktemp -d -p "$aosp_root/out" kiki-services-delta.XXXXXX)
case "$tmp" in
    "$aosp_root"/out/kiki-services-delta.*) ;;
    *) echo "temporary extraction escaped AOSP out/: $tmp" >&2; exit 2 ;;
esac
cleanup_tmp() {
    find "$tmp" -type d -exec chmod u+rwx {} + 2>/dev/null || true
    rm -rf -- "$tmp"
}
trap cleanup_tmp EXIT
mkdir -p "$tmp/root"
fsck.erofs --extract="$tmp/root" "$base" >"$tmp/extract.log" 2>&1

base_system="$tmp/root/system"
[[ -d "$base_system/framework/oat/arm64" && -f "$base_system/framework/services.jar" ]] || {
    echo "frozen image lacks its expected Android services runtime" >&2
    exit 2
}

# The ranchu first-stage flow switches / to the system EROFS image. Ensure its
# root contains the /data_mirror mountpoint required by init.rc; adding it only
# to the generic ramdisk is insufficient because that root is replaced.
install -d -m 0755 "$tmp/root/data_mirror"

# Overlay only the matching services runtime. Settings, Launcher3, SystemUI,
# graphics, ADB, and the independent supporting partitions remain unchanged.
install -D -m 0644 "$services_jar" "$base_system/framework/services.jar"
install -D -m 0644 "$services_prof" "$base_system/framework/services.jar.prof"
for artifact in services.odex services.vdex services.art; do
    install -D -m 0644 "$services_oat/$artifact" "$base_system/framework/oat/arm64/$artifact"
done

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
    cp --reflink=auto -- "$base_stem-$partition.img" "$output_stem-$partition.img"
done
mv -- "$tmp/system.img" "$output"
sha256sum "$output" "$output_stem-vendor.img" "$output_stem-product.img" \
    "$output_stem-system_ext.img"
