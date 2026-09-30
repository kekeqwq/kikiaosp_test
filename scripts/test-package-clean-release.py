#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Isolated NONBOOTABLE packaging helper tests, no build/VM/user installation."""
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("packager", Path(__file__).with_name("package-clean-release.py"))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)
fixtures = packager.load_module("nonbootable_fixtures", "test-system-package.py")


class Guards(unittest.TestCase):
    def test_incomplete_and_development_inputs_never_reach_git(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prep, record = root / "prep", root / "build"
            prep.mkdir()
            record.mkdir()
            for status, phase, product in (
                    ("preparing-source-not-built", packager.FINISHED_PHASE, "kikiaosp_test_arm64_phone_release"),
                    ("clean-pinned-upstream-ready-not-built", "building-aosp", "kikiaosp_test_arm64_phone_release"),
                    ("clean-pinned-upstream-ready-not-built", packager.FINISHED_PHASE, "kikiaosp_test_arm64_phone")):
                (prep / "prepare.json").write_text(json.dumps({"status": status, "branch": "android17-release"}))
                (record / "build-audit.json").write_text(json.dumps({"phase": phase, "product": product,
                                                                    "recipe": "kikiaosp-release-v1", "systemVersion": "0.1.0-alpha"}))
                with patch.object(packager.builder, "run") as run:
                    with self.assertRaises(ValueError):
                        packager.audit_inputs(prep, record)
                    run.assert_not_called()

    def test_input_hash_and_length_cannot_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "image.img"
            path.write_bytes(b"fresh build input")
            expected = packager.file_record(path)
            packager.verify_record(path, expected)
            path.write_bytes(b"changed build input")
            with self.assertRaises(ValueError):
                packager.verify_record(path, expected)

    def test_symlink_input_cannot_replace_regular_image(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "original").write_bytes(b"real")
            (root / "redirect").symlink_to(root / "original")
            with self.assertRaises(ValueError):
                packager.file_record(root / "redirect")

    def test_license_splitting_preserves_every_byte_and_utf8(self):
        for raw, limit in ((b"abc\n" * 70, 37), (("Copyright 可爱\n" * 40).encode(), 29), ("啊".encode() * 30, 10)):
            parts = packager.license_parts(raw, limit)
            self.assertEqual(b"".join(parts), raw)
            self.assertTrue(all(0 < len(part) <= limit for part in parts))
            for part in parts:
                part.decode("utf-8")
        with self.assertRaises(ValueError):
            packager.license_parts(b"")

    def test_notice_bodies_and_attribution_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "NOTICE.xml.gz"
            path.write_bytes(gzip.compress(b'<licenses><file-name contentId="a">/system/bin/sample</file-name>'
                                           b'<file-content contentId="a"><![CDATA[Copyright example\nPermission text.]]></file-content></licenses>'))
            result = packager.notice_text(path)
            self.assertIn(b"/system/bin/sample", result)
            self.assertIn(b"Copyright example\nPermission text.", result)

    def test_notice_entities_and_incomplete_license_text_reject(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "NOTICE.xml.gz"
            for raw in (b'<!DOCTYPE licenses [<!ENTITY x "unknown">]><licenses/>',
                        b'<licenses><file-name contentId="missing">/system/bin/x</file-name></licenses>'):
                path.write_bytes(gzip.compress(raw))
                with self.assertRaises(ValueError):
                    packager.notice_text(path)

    def test_generated_notice_bytes_are_not_silently_reformatted(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "NOTICE.xml.gz"
            raw = b'<licenses><file-content contentId="a"><![CDATA[Original third-party byte: \x01]]></file-content></licenses>'
            path.write_bytes(gzip.compress(raw))
            self.assertEqual(packager.notice_text(path), raw)

    def test_packaged_properties_are_release_identity_not_staging_claim(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "etc").mkdir()
            path = root / "etc/build.prop"
            good = {**packager.RELEASE_PROPERTIES, "ro.product.system.model": packager.MODEL, "ro.build.version.release": "17"}
            path.write_text("\n".join(key + "=" + value for key, value in good.items()))
            packager.image_properties(root)
            path.write_text(path.read_text().replace("ro.kikiaosp.build_channel=release", "ro.kikiaosp.build_channel=dev"))
            with self.assertRaises(ValueError):
                packager.image_properties(root)

    def test_wrong_raw_filesystem_rejects_without_running_tool(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "wrong.img").write_bytes(b"not an EROFS image")
            with patch.object(packager.builder, "run") as run:
                with self.assertRaises(ValueError):
                    packager.raw_erofs(root / "wrong.img", root / "target.img", root)
                run.assert_not_called()
            self.assertFalse((root / "target.img").exists())

    def test_zip_is_deterministic_allowlisted_and_not_overwritten(self):
        with tempfile.TemporaryDirectory(prefix="kiki-NONBOOTABLE-package-test-") as directory:
            root = Path(directory)
            members = {}
            for name, data in fixtures.fixture_files().items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
                members[name] = path
            first, second = root / "NONBOOTABLE-first.zip", root / "NONBOOTABLE-second.zip"
            packager.write_zip(first, members)
            packager.write_zip(second, members)
            packager.validator.validate_package(first)
            self.assertEqual(hashlib.sha256(first.read_bytes()).digest(), hashlib.sha256(second.read_bytes()).digest())
            before = first.read_bytes()
            with self.assertRaises(FileExistsError):
                packager.write_zip(first, members)
            self.assertEqual(before, first.read_bytes())

    def test_frozen_contract_hashes_still_match_consumer_pin(self):
        for name, expected in packager.CONTRACT_HASHES.items():
            self.assertEqual(packager.builder.digest(packager.validator.CONTRACT / name), expected)


if __name__ == "__main__":
    unittest.main()
