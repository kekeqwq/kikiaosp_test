#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Isolated NONBOOTABLE producer fixtures, never a release build or installer."""
import argparse
import copy
import hashlib
import importlib.util
import json
import struct
import tempfile
import warnings
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("package_validator", Path(__file__).with_name("system-package.py"))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fixture_files():
    manifest = validator.document((validator.CONTRACT / "fixtures.json").read_bytes())["validManifest"]
    boot = bytearray(12288)
    boot[:8] = b"ANDROID!"
    for offset, value in ((8, 64), (12, 32), (20, 1584), (40, 4), (4120, 2)):
        struct.pack_into("<I", boot, offset, value)
    boot[4152:4156] = b"ARM\x64"
    boot[8192:8195] = b"\x1f\x8b\x08"
    erofs = bytearray(4096)
    erofs[1024:1028] = b"\xe2\xe1\xf5\xe0"
    xml = '<manifest><project name="platform/synthetic-not-bootable" path="synthetic" revision="' + 'a' * 40 + '"/></manifest>'
    lock = {
        "sourceLockVersion": 1,
        "contract": {"repository": "https://github.com/kekeqwq/kikiaosp_test", "revision": "a" * 40,
                     "manifestSchemaSha256": digest((validator.CONTRACT / "manifest.schema.json").read_bytes()),
                     "sourceLockSchemaSha256": digest((validator.CONTRACT / "source-lock.schema.json").read_bytes())},
        "aosp": {"branch": "android17-release", "manifestXml": xml, "manifestSha256": digest(xml.encode()), "projectCount": 1},
        "device": {"repository": "https://github.com/kekeqwq/kikiaosp_test", "commit": "b" * 40},
        "kernel": {"repository": "https://github.com/kekeqwq/kikiaosp_kernel", "commit": "c" * 40,
                   "flakeLockSha256": "d" * 64, "sourceVersion": "7.3-rc4", "imageSha256": digest(boot[4096:4160])},
        "build": {"cleanSource": True, "independentOutput": True, "outputRecipe": "kikiaosp-release-v1",
                  "tools": {"mkbootfsSha256": "e" * 64, "mkbootimgSha256": "f" * 64, "mkfsErofsSha256": "0" * 64}}
    }
    files = {"payload/boot.img": bytes(boot), "payload/system.img": bytes(erofs), "payload/vendor.img": bytes(erofs),
             "provenance/source-lock.json": json.dumps(lock).encode(),
             "licenses/aosp.txt": b"SYNTHETIC internal fixture, NOT AOSP redistributable",
             "licenses/kernel.txt": b"SYNTHETIC internal fixture, NOT Linux redistributable"}
    for record in [*manifest["payloads"], manifest["sourceLock"], *manifest["licenses"]]:
        data = files[record["path"]]
        record["bytes"], record["sha256"] = len(data), digest(data)
    files = {"manifest.json": json.dumps(manifest).encode(), **files}
    return files


def write_zip(path, files, compression=zipfile.ZIP_STORED, local_zip64=False):
    with zipfile.ZipFile(path, "x", compression=compression, allowZip64=True) as archive:
        for name, data in files.items():
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = compression
            with archive.open(info, "w", force_zip64=local_zip64) as output:
                output.write(data)


def check_rejected(path, name):
    try:
        validator.validate_package(path)
    except Exception:
        return
    raise AssertionError(f"Invalid package accepted: {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--export-fixture", type=Path, help="Optional new NOT-BOOTABLE.zip for native cross-reader unit tests, NOT a user system ZIP")
    args = parser.parse_args()
    validator.fixture_checks()
    files = fixture_files()
    checks = 0
    with tempfile.TemporaryDirectory(prefix="kikiaosp-package-fixtures-") as temporary:
        root = Path(temporary)
        for name, compression, local_zip64 in (("store", zipfile.ZIP_STORED, False), ("deflate", zipfile.ZIP_DEFLATED, False),
                                               ("local-zip64", zipfile.ZIP_STORED, True)):
            path = root / f"{name}.zip"
            write_zip(path, files, compression, local_zip64)
            validator.validate_package(path)
            checks += 1
        base = (root / "store.zip").read_bytes()
        mutations = {"prefix": b"MZ-not-a-release" + base, "trailer": base + b"hidden bytes",
                     "truncated": base[:-1], "comment": base[:-2] + b"\x01\x00x"}
        central = base.index(b"PK\x01\x02")
        nul = bytearray(base)
        nul[central + 46 + 4] = 0
        mutations["nul-path"] = nul
        local = bytearray(base)
        local[30] = ord("x")
        mutations["local-central-mismatch"] = local
        for name, data in mutations.items():
            path = root / f"{name}.zip"
            path.write_bytes(data)
            check_rejected(path, name)
            checks += 1
        for name, altered in (("forbidden", {**files, "userdata.img": b"never ship userdata"}),
                              ("missing", {key: data for key, data in files.items() if key != "payload/vendor.img"}),
                              ("bad-sha", {**files, "payload/vendor.img": b"x" * 4096})):
            path = root / f"{name}.zip"
            write_zip(path, altered)
            check_rejected(path, name)
            checks += 1
        duplicate = root / "duplicate.zip"
        write_zip(duplicate, files)
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(duplicate, "a") as archive:
                archive.writestr("manifest.json", files["manifest.json"])
        check_rejected(duplicate, "duplicate")
        checks += 1
        lock = validator.document(files["provenance/source-lock.json"])
        for name, xml in (("nested", '<manifest><group><project name="hidden" revision="' + 'a' * 40 + '"/></group><project name="valid" revision="' + 'b' * 40 + '"/></manifest>'),
                          ("dtd", '<!DOCTYPE manifest [<!ENTITY x "secret">]><manifest><project name="valid" revision="' + 'b' * 40 + '"/></manifest>')):
            bad = copy.deepcopy(lock)
            bad["aosp"]["manifestXml"] = xml
            bad["aosp"]["manifestSha256"] = digest(xml.encode())
            try:
                validator.validate_lock(bad)
            except Exception:
                checks += 1
            else:
                raise AssertionError(f"Invalid provenance accepted: {name}")
    if args.export_fixture:
        if not args.export_fixture.name.endswith("NOT-BOOTABLE.zip"):
            parser.error("Export filename must end in NOT-BOOTABLE.zip.")
        write_zip(args.export_fixture, files, zipfile.ZIP_DEFLATED, True)
        print(f"Exported SYNTHETIC NONBOOTABLE cross-reader fixture: {args.export_fixture}")
    print(f"PASS: {checks} isolated producer ZIP/provenance checks; no real system/package/installation changes.")


if __name__ == "__main__":
    main()
