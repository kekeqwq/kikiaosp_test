#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build direct-boot material from THIS AOSP product's static first-stage init.

No frozen ramdisk, recovery image, Cuttlefish archive or used disk is an input.
This development prototype does not certify a clean release build. The release
producer must separately enforce a frozen source lock and independent outputs.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def check_static_init(path):
    with path.open("rb") as stream:
        header = stream.read(64)
        if header[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", header, 18)[0] != 183:
            raise ValueError("First-stage init must be a little-endian AArch64 ELF64 file.")
        phoff = struct.unpack_from("<Q", header, 32)[0]
        phsize, count = struct.unpack_from("<HH", header, 54)
        if phsize != 56 or count > 256:
            raise ValueError("Invalid first-stage init program headers.")
        for index in range(count):
            stream.seek(phoff + index * phsize)
            program = stream.read(phsize)
            if len(program) != phsize or struct.unpack_from("<I", program)[0] == 3:
                raise ValueError("First-stage init is truncated or needs a dynamic linker.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aosp", required=True, type=Path)
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--product", default="kikiaosp_test")
    parser.add_argument("--fstab", type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    aosp, kernel, output = args.aosp.resolve(), args.kernel.resolve(), args.output.resolve()
    if not (aosp / ".repo/manifest.xml").is_file():
        raise ValueError("AOSP root is not a repo checkout.")
    if args.product != "kikiaosp_test":
        raise ValueError("Only the KikiAOSP device product is supported.")
    out = Path(os.environ.get("OUT_DIR", str(aosp / "out")))
    if not out.is_absolute():
        out = aosp / out
    product = out / "target/product" / args.product
    tools = out / "host/linux-x86/bin"
    init = product / "ramdisk/init"
    check_static_init(init)
    with kernel.open("rb") as stream:
        if stream.read(64)[56:60] != b"ARM\x64":
            raise ValueError("Kernel must be the uncompressed AArch64 Linux Image.")
    fstab = (args.fstab or repo / "device/kiki/kikiaosp_test/fstab.ranchu").resolve()
    if not fstab.is_file() or repo not in fstab.parents:
        raise ValueError("fstab must be a tracked recipe inside this device repository.")
    relative_fstab = fstab.relative_to(repo).as_posix()
    subprocess.run(["git", "-C", str(repo), "ls-files", "--error-unmatch", relative_fstab],
                   check=True, stdout=subprocess.DEVNULL)
    if output.exists():
        raise ValueError("Output must be a NEW directory; existing artifacts are never overwritten.")
    for name in ("mkbootfs", "mkbootimg"):
        if not (tools / name).is_file():
            raise ValueError(f"Build the AOSP host tool first: {name}.")
    output.mkdir(parents=True)
    root = output / "ramdisk-root"
    root.mkdir()
    # The built generic ramdisk contains the statically linked first-stage
    # init plus empty mount points. Do not copy product/root, system/lib*,
    # precompiled linker configuration or a historical recovery userspace.
    shutil.copyfile(init, root / "init")
    (root / "init").chmod(0o755)
    first = root / "first_stage_ramdisk"
    for base in (root, first):
        for directory in ("dev", "proc", "sys", "mnt", "metadata", "second_stage_resources", "debug_ramdisk"):
            (base / directory).mkdir(parents=True, exist_ok=True)
    first_fstab = first / "system/etc/fstab.ranchu"
    first_fstab.parent.mkdir(parents=True)
    shutil.copyfile(fstab, first_fstab)
    # force_normal_boot switches into /first_stage_ramdisk before fs_mgr reads
    # the hardware fstab. Mounting /system then supplies the complete SAR root,
    # second-stage init, bootstrap linker, policy and APEX userspace from AOSP.
    for entry in sorted(root.rglob("*")) + [root]:
        os.utime(entry, (0, 0))
    ramdisk = output / "ramdisk.img"
    with ramdisk.open("wb") as raw:
        process = subprocess.Popen([str(tools / "mkbootfs"), str(root)], stdout=subprocess.PIPE)
        try:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
                shutil.copyfileobj(process.stdout, compressed)
        finally:
            process.stdout.close()
        if process.wait():
            raise ValueError("AOSP mkbootfs failed.")
    boot = output / "boot.img"
    subprocess.run([str(tools / "mkbootimg"), "--header_version", "4", "--kernel", str(kernel),
                    "--ramdisk", str(ramdisk), "--output", str(boot)], check=True)
    device_commit = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    recipe = {
        "recipeVersion": 1, "status": "development-prototype-not-release-certified",
        "product": args.product, "bootHeaderVersion": 4, "deviceCommit": device_commit,
        "fstabPath": relative_fstab, "fstabSha256": digest(fstab),
        "inputs": {"staticInitSha256": digest(init), "kernelSha256": digest(kernel),
                   "mkbootfsSha256": digest(tools / "mkbootfs"), "mkbootimgSha256": digest(tools / "mkbootimg")},
        "outputs": {name: {"bytes": path.stat().st_size, "sha256": digest(path)}
                    for name, path in (("ramdisk.img", ramdisk), ("boot.img", boot))},
    }
    (output / "boot-recipe.json").write_text(json.dumps(recipe, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(recipe, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
