#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 AOSP_ROOT" >&2
    exit 2
fi

aosp_root=$(realpath "$1")
[[ -f "$aosp_root/.repo/manifest.xml" ]] || {
    echo "not an AOSP checkout: $aosp_root" >&2
    exit 2
}

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$repo_root/device/kiki/kikiaosp_test"
target_parent=$(realpath -m "$aosp_root/device/kiki")
case "$target_parent/" in
    "$aosp_root/"*) ;;
    *) echo "device/kiki resolves outside the AOSP checkout: $target_parent" >&2; exit 2 ;;
esac
target_dir="$target_parent/kikiaosp_test"
if [[ -L "$target_dir" ]]; then
    echo "refusing symlink device-tree destination: $target_dir" >&2
    exit 2
fi
mkdir -p "$target_dir"
cp -a "$source_dir/." "$target_dir/"
echo "Synchronized $source_dir -> $target_dir (does not remove stale destination files)"
