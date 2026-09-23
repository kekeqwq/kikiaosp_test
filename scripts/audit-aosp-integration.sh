#!/usr/bin/env bash
set -euo pipefail
AOSP_ROOT=${1:-}
REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [[ -z "$AOSP_ROOT" || ! -d "$AOSP_ROOT/.repo" ]]; then echo "usage: $0 /path/to/aosp-master" >&2; exit 2; fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
awk '/^diff --git a\\// {print $3}' "$REPO_ROOT/patches/aosp-working-tree.patch" | sed 's#^a/##' | sort -u > "$tmp/expected"
( cd "$AOSP_ROOT"; repo forall -c 'git diff --name-only | sed "s#^#$REPO_PATH/#"' ) | sed '/^$/d' | sort -u > "$tmp/actual"
if ! diff -u "$tmp/expected" "$tmp/actual"; then echo "AOSP tracked changes do not exactly match kikiaosp_test/patches" >&2; exit 1; fi
find "$REPO_ROOT/overlays" -type f -printf '%P\\n' | sort -u > "$tmp/expected-untracked"
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
