#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output=${1:-"$repo_dir/out/kiki_black_scanout"}
variant=${2:-black}
compiler=${CROSS_CC:-aarch64-unknown-linux-gnu-gcc}
variant_flags=()
case "$variant" in
    black) ;;
    test-ui) variant_flags+=(-DKIKI_TEST_UI) ;;
    *) echo "unknown scanout variant: $variant" >&2; exit 2 ;;
esac
mkdir -p -- "$(dirname -- "$output")"
"$compiler" -nostdlib -static -ffreestanding -fno-builtin \
    -fno-stack-protector -O2 -Wall -Wextra -Werror "${variant_flags[@]}" \
    -o "$output" "$repo_dir/device/kiki/kikiaosp_test/kiki_black_scanout.c"
file "$output"
