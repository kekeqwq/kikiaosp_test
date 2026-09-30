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
    def invalid_constant(value):
        raise ValueError(f"Nonstandard JSON constant: {value}")
    return json.loads(data.decode("utf-8"), object_pairs_hook=no_duplicates, parse_constant=invalid_constant)


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
    remaining = [(root, 0)]
    while remaining:
        node, depth = remaining.pop()
        if depth >= 32 or (node.tag == "project" and depth != 1):
            raise ValueError("Excessively nested/noncanonical AOSP provenance.")
        remaining.extend((child, depth + 1) for child in node)
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


def raw_zip_names(path):
    """Strict raw metadata checks matching the native consumer.

    zipfile owns CRC/decompression; preflight forbids formats it would otherwise
    normalize (NULs, executable prefixes, comments/trailers and aliases).
    """
    length = path.stat().st_size
    with path.open("rb") as stream:
        def read(at, count):
            if at < 0 or at > length or count > length - at:
                raise ValueError("ZIP metadata is out of bounds.")
            stream.seek(at)
            value = stream.read(count)
            if len(value) != count:
                raise ValueError("ZIP metadata is truncated.")
            return value
        def number(data, at, width):
            return int.from_bytes(data[at:at + width], "little")
        if length < 22 or read(0, 4) != b"PK\x03\x04":
            raise ValueError("System package must be a ZIP, not SFX/executable.")
        end = read(length - 22, 22)
        if (end[:4] != b"PK\x05\x06" or number(end, 20, 2) or number(end, 4, 2) or
                number(end, 6, 2) or number(end, 8, 2) != number(end, 10, 2)):
            raise ValueError("Multi-disk/commented/trailing ZIP data is unsupported.")
        entries, size, offset = number(end, 10, 2), number(end, 12, 4), number(end, 16, 4)
        central_end = length - 22
        if entries == 65535 or size == 4294967295 or offset == 4294967295:
            locator = read(length - 42, 20)
            if locator[:4] != b"PK\x06\x07" or number(locator, 4, 4) or number(locator, 16, 4) != 1:
                raise ValueError("Invalid ZIP64 locator.")
            record_at = number(locator, 8, 8)
            record = read(record_at, 56)
            if (record[:4] != b"PK\x06\x06" or number(record, 4, 8) != 44 or
                    record_at + 56 != length - 42 or number(record, 16, 4) or number(record, 20, 4) or
                    number(record, 24, 8) != number(record, 32, 8)):
                raise ValueError("Invalid ZIP64 end record.")
            entries, size, offset = number(record, 32, 8), number(record, 40, 8), number(record, 48, 8)
            central_end = record_at
        if not 1 <= entries <= 69 or size > 1048576 or offset > central_end or size != central_end - offset:
            raise ValueError("ZIP directory count/size/offset is unsupported.")
        names = set()
        cursor = offset
        for _ in range(entries):
            header = read(cursor, 46)
            if header[:4] != b"PK\x01\x02" or number(header, 8, 2) & 1 or number(header, 34, 2):
                raise ValueError("Invalid/encrypted/multi-disk ZIP entry.")
            name_bytes, extra, comment = number(header, 28, 2), number(header, 30, 2), number(header, 32, 2)
            if not 1 <= name_bytes <= 128 or comment or cursor + 46 + name_bytes + extra > central_end:
                raise ValueError("Noncanonical ZIP entry metadata.")
            name = read(cursor + 46, name_bytes).decode("ascii")
            if (not re.fullmatch(r"(?:manifest[.]json|payload/(?:boot|system|vendor)[.]img|provenance/source-lock[.]json|licenses/[a-z0-9][a-z0-9_-]*[.]txt)", name)
                    or name in names):
                raise ValueError("Duplicate or unsafe raw ZIP pathname.")
            names.add(name)
            local_at = number(header, 42, 4)
            if local_at == 4294967295:
                fields = read(cursor + 46 + name_bytes, extra)
                at, found = 0, False
                while at + 4 <= len(fields):
                    tag, field_length = number(fields, at, 2), number(fields, at + 2, 2)
                    at += 4
                    if field_length > len(fields) - at:
                        raise ValueError("Truncated ZIP64 extra field.")
                    if tag == 1:
                        skip = (8 if number(header, 24, 4) == 4294967295 else 0) + (8 if number(header, 20, 4) == 4294967295 else 0)
                        if found or skip + 8 > field_length:
                            raise ValueError("Missing/duplicate ZIP64 local offset.")
                        local_at, found = number(fields, at + skip, 8), True
                    at += field_length
                if not found:
                    raise ValueError("ZIP64 local offset was not declared.")
            if local_at >= offset:
                raise ValueError("ZIP local header overlaps its directory.")
            local = read(local_at, 30)
            local_name_bytes, local_extra = number(local, 26, 2), number(local, 28, 2)
            method = number(header, 10, 2)
            if (local[:4] != b"PK\x03\x04" or local_name_bytes != name_bytes or
                    local_at + 30 + local_name_bytes + local_extra > offset or method not in (0, 8) or
                    number(local, 8, 2) != method or number(local, 6, 2) != number(header, 8, 2) or
                    read(local_at + 30, local_name_bytes) != name.encode("ascii")):
                raise ValueError("ZIP local/central name, flags or compression differ.")
            cursor += 46 + name_bytes + extra
        if cursor != central_end:
            raise ValueError("Unrecognized ZIP directory extension.")
        return names


def validate_package(path):
    if path.stat().st_size > 32 << 30:
        raise ValueError("ZIP exceeds format-1 safety limit.")
    raw_names = raw_zip_names(path)
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
        if names != raw_names:
            raise ValueError("Decoded ZIP names differ from raw metadata.")
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
