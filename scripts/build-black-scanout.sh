#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output=${1:-"$repo_dir/out/kiki_black_scanout"}
compiler=${CROSS_CC:-aarch64-unknown-linux-gnu-gcc}
mkdir -p -- "$(dirname -- "$output")"
"$compiler" -nostdlib -static -ffreestanding -fno-builtin \
    -fno-stack-protector -O2 -Wall -Wextra -Werror \
    -o "$output" "$repo_dir/device/kiki/kikiaosp_test/kiki_black_scanout.c"
file "$output"
