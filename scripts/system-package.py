#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Canonical format-1 metadata/package validator and fixture checks.

Requires python-jsonschema. This does not rename development artifacts into
release packages, create userdata, install a manager or execute package content.
"""
import argparse
import hashlib
import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from jsonschema import Draft202012Validator

CONTRACT = Path(__file__).resolve().parent.parent / "contracts/format-1"
LAUNCHER_VERSION = "0.1.0-alpha"
ALIGN = 1048576
MAX_TOTAL = 32 << 30


def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def document(data):
    return json.loads(data.decode("utf-8"), object_pairs_hook=no_duplicates)


def schema(name):
    value = document((CONTRACT / name).read_bytes())
    Draft202012Validator.check_schema(value)
    return Draft202012Validator(value)


def version(value):
    match = re.fullmatch(r"(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)(?:-([a-z0-9.-]+))?", value)
    if not match:
        raise ValueError("Unsupported version syntax.")
    numbers = tuple(int(match[i]) for i in range(1, 4))
    if any(number > 18446744073709551615 for number in numbers):
        raise ValueError("Version component exceeds the supported integer range.")
    if match[4] is None:
        return numbers + (1, ())
    identifiers = match[4].split(".")
    if any(not part or (part.isdecimal() and len(part) > 1 and part.startswith("0")) for part in identifiers):
        raise ValueError("Noncanonical version prerelease identifiers.")
    return numbers + (0, tuple((0, int(part)) if part.isdecimal() else (1, part) for part in identifiers))


def validate_manifest(value):
    # Our canonical integer-byte encoding does not admit JSON booleans or
    # decimal tokens even when a general JSON Schema library calls 1.0 integer.
    for key in ("formatVersion", "pageSizeBytes", "sectorSizeBytes", "alignmentBytes", "minimumDataBytes"):
        if type(value.get(key)) is not int:
            raise ValueError("Format-1 byte/version integers must use integer tokens.")
    for entry in value.get("payloads", []):
        for key in ("bytes", "partitionBytes"):
            if type(entry.get(key)) is not int:
                raise ValueError("Payload sizes must be integer tokens.")
    for entry in [value.get("sourceLock", {}), *value.get("licenses", [])]:
        if type(entry.get("bytes")) is not int:
            raise ValueError("Record lengths must be integer tokens.")
    schema("manifest.schema.json").validate(value)
    version(value["systemVersion"])
    if version(value["minimumLauncherVersion"]) > version(LAUNCHER_VERSION):
        raise ValueError("System requires a newer KikiEmu reader.")
    records = {"manifest.json": None}
    roles = set()
    total = 0
    for entry in value["payloads"]:
        role = entry["role"]
        expected_format = "android-boot-v4" if role == "boot" else "raw-erofs"
        if role in roles or entry["path"] != f"payload/{role}.img" or entry["imageFormat"] != expected_format:
            raise ValueError("Missing/duplicate/mismatched partition role, path or encoding.")
        if entry["partitionBytes"] != (entry["bytes"] + ALIGN - 1) // ALIGN * ALIGN:
            raise ValueError("Payload partition size does not match canonical rounding.")
        roles.add(role)
        records[entry["path"]] = entry
        total += entry["bytes"]
    if roles != {"boot", "system", "vendor"}:
        raise ValueError("All three partition roles are required.")
    for entry in [value["sourceLock"], *value["licenses"]]:
        if entry["path"] in records:
            raise ValueError("Duplicate file declaration.")
        records[entry["path"]] = entry
        total += entry["bytes"]
    if not {"licenses/aosp.txt", "licenses/kernel.txt"}.issubset(records):
        raise ValueError("AOSP and kernel license records are required.")
    if total > MAX_TOTAL:
        raise ValueError("Unpacked package exceeds format-1 safety limit.")
    return records


def validate_lock(value):
    schema("source-lock.schema.json").validate(value)
    raw = value["aosp"]["manifestXml"].encode("utf-8")
    if len(raw) > 4194304 or type(value["sourceLockVersion"]) is not int or type(value["aosp"]["projectCount"]) is not int:
        raise ValueError("Invalid bounded source-lock integer/XML encoding.")
    if hashlib.sha256(raw).hexdigest() != value["aosp"]["manifestSha256"]:
        raise ValueError("Pinned AOSP manifest digest mismatch.")
    if b"<!DOCTYPE" in raw or b"<!ENTITY" in raw:
        raise ValueError("External/entity declarations are forbidden in provenance.")
    root = ET.fromstring(raw)
    projects = root.findall("project")
    if root.tag != "manifest" or len(projects) != value["aosp"]["projectCount"]:
        raise ValueError("Pinned project count/root mismatch.")
    paths = set()
    for project in projects:
        path = project.get("path", project.get("name", ""))
        if not path or path.startswith("/") or "\\" in path or ":" in path or any(part in ("", ".", "..") for part in path.split("/")):
            raise ValueError("AOSP provenance contains an unsafe/absolute project path.")
        if path in paths or not re.fullmatch(r"[0-9a-f]{40}", project.get("revision", "")):
            raise ValueError("AOSP projects must be uniquely pinned to full commits.")
        paths.add(path)
    for name, field in (("manifest.schema.json", "manifestSchemaSha256"), ("source-lock.schema.json", "sourceLockSchemaSha256")):
        if hashlib.sha256((CONTRACT / name).read_bytes()).hexdigest() != value["contract"][field]:
            raise ValueError("Package contract bytes differ from this reader's pinned schema.")


def boot_header(data, length):
    if len(data) < 4096 or data[:8] != b"ANDROID!" or struct.unpack_from("<I", data, 40)[0] != 4:
        raise ValueError("Unsupported boot header.")
    kernel, ramdisk = struct.unpack_from("<II", data, 8)
    if struct.unpack_from("<I", data, 20)[0] != 1584 or any(data[24:40]) or any(data[44:4096]):
        raise ValueError("Boot signatures/reserved/cmdline/padding are not supported.")
    if not 64 <= kernel <= 256 << 20 or not 10 <= ramdisk <= 64 << 20:
        raise ValueError("Boot component size is invalid.")
    ramdisk_offset = 4096 + (kernel + 4095) // 4096 * 4096
    if length != ramdisk_offset + (ramdisk + 4095) // 4096 * 4096:
        raise ValueError("Truncated/trailing boot data.")
    return kernel, ramdisk, ramdisk_offset


def validate_package(path):
    if path.stat().st_size > 32 << 30:
        raise ValueError("ZIP exceeds format-1 safety limit.")
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        names, folded = set(), set()
        if len(infos) > 69:
            raise ValueError("Too many archive entries.")
        for info in infos:
            name = info.filename
            if not re.fullmatch(r"(?:manifest[.]json|payload/(?:boot|system|vendor)[.]img|provenance/source-lock[.]json|licenses/[a-z0-9][a-z0-9_-]*[.]txt)", name):
                raise ValueError("Forbidden/noncanonical archive path.")
            mode = info.external_attr >> 16
            if info.is_dir() or info.flag_bits & 1 or (mode & 0o170000) not in (0, 0o100000):
                raise ValueError("Directory/encrypted/symlink/special archive entry.")
            if name in names or name.casefold() in folded or not 0 < info.file_size <= MAX_TOTAL:
                raise ValueError("Duplicate, case-ambiguous or oversized archive entry.")
            names.add(name)
            folded.add(name.casefold())
        if "manifest.json" not in names or archive.getinfo("manifest.json").file_size > 1048576:
            raise ValueError("Missing/oversized manifest.")
        manifest = document(archive.read("manifest.json"))
        records = validate_manifest(manifest)
        if names != set(records):
            raise ValueError("Archive differs from manifest allowlist.")
        lock = None
        kernel_hash = None
        for name, record in records.items():
            if record is None:
                continue
            info = archive.getinfo(name)
            if info.file_size != record["bytes"]:
                raise ValueError("Declared file length mismatch.")
            digest = hashlib.sha256()
            header = bytearray()
            captured = bytearray() if name == "provenance/source-lock.json" else None
            boot = None
            kernel_digest = hashlib.sha256()
            ramdisk_magic = bytearray()
            offset = 0
            with archive.open(name) as stream:
                while data := stream.read(1048576):
                    digest.update(data)
                    if len(header) < 4096:
                        header += data[:4096 - len(header)]
                    if captured is not None:
                        captured += data
                    if name == "payload/boot.img":
                        if boot is None:
                            boot = boot_header(header, info.file_size)
                        kernel, _, ramdisk_at = boot
                        begin, end = max(4096, offset), min(4096 + kernel, offset + len(data))
                        if begin < end:
                            kernel_digest.update(data[begin - offset:end - offset])
                        begin, end = max(ramdisk_at, offset), min(ramdisk_at + 3, offset + len(data))
                        if begin < end:
                            ramdisk_magic += data[begin - offset:end - offset]
                        if offset == 0 and (data[4152:4156] != b"ARM\x64" or ((struct.unpack_from("<Q", data, 4120)[0] >> 1) & 3) != 1):
                            raise ValueError("Kernel is not a 4-KiB AArch64 Image.")
                    offset += len(data)
            if digest.hexdigest() != record["sha256"] or offset != record["bytes"]:
                raise ValueError("Payload SHA/length mismatch.")
            if name in ("payload/system.img", "payload/vendor.img") and header[1024:1028] != b"\xe2\xe1\xf5\xe0":
                raise ValueError("Filesystem must be raw EROFS, not sparse/whole-disk.")
            if name == "payload/boot.img":
                if ramdisk_magic != b"\x1f\x8b\x08":
                    raise ValueError("Ramdisk must be gzip.")
                kernel_hash = kernel_digest.hexdigest()
            if captured is not None:
                lock = document(captured)
        validate_lock(lock)
        if kernel_hash != lock["kernel"]["imageSha256"]:
            raise ValueError("Source-lock kernel identity does not match boot payload.")
    return manifest


def assign_pointer(value, pointer, replacement):
    parts = pointer.lstrip("/").split("/")
    target = value
    for part in parts[:-1]:
        target = target[int(part)] if isinstance(target, list) else target[part]
    if isinstance(target, list):
        target[int(parts[-1])] = replacement
    else:
        target[parts[-1]] = replacement


def fixture_checks():
    fixtures = document((CONTRACT / "fixtures.json").read_bytes())
    validate_manifest(fixtures["validManifest"])
    count = 1
    for case in fixtures["negativeMutations"]:
        value = json.loads(json.dumps(fixtures["validManifest"]))
        assign_pointer(value, case["pointer"], case["value"])
        try:
            validate_manifest(value)
        except Exception:
            count += 1
        else:
            raise ValueError(f"Negative fixture accepted: {case['name']}")
    print(f"PASS: {count} canonical manifest metadata fixtures; no release package generated.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--validate", type=Path)
    args = parser.parse_args()
    if args.self_test:
        fixture_checks()
    elif args.validate:
        value = validate_package(args.validate)
        print(f"Validated format-1 system package: {value['systemVersion']}")
    else:
        parser.error("Use --self-test or --validate ZIP.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
