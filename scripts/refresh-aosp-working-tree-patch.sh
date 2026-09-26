#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 /path/to/aosp-checkout" >&2
    exit 2
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
aosp_root=$(realpath -e -- "$1")
[[ -d "$aosp_root/.repo" ]] || { echo "not an AOSP checkout: $aosp_root" >&2; exit 2; }

scratch=$(mktemp "$repo_root/patches/.aosp-working-tree.XXXXXX.patch")
trap 'rm -f -- "$scratch"' EXIT
(
    cd "$aosp_root"
    repo forall -c 'git diff --binary --src-prefix="a/$REPO_PATH/" --dst-prefix="b/$REPO_PATH/"'
) > "$scratch"
[[ -s "$scratch" ]] || { echo "AOSP has no tracked source changes" >&2; exit 1; }
patch -d "$aosp_root" -p1 --dry-run --reverse --batch < "$scratch" >/dev/null
mv -- "$scratch" "$repo_root/patches/aosp-working-tree.patch"
echo "Refreshed patches/aosp-working-tree.patch from current tracked AOSP changes"
