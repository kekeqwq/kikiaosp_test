#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Isolated tests of manifest portability; no repo checkout/network changes."""
import importlib.util
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("prepare", Path(__file__).with_name("prepare-clean-release.py"))
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class ManifestTests(unittest.TestCase):
    def test_relative_remote_preserves_projects(self):
        raw = (b'<manifest><remote name="aosp" fetch=".."/><default revision="android17-release"/>'
               b'<project name="platform/example" path="example" revision="' + b'a' * 40 + b'"/></manifest>')
        fixed, count = prepare.portable_manifest(raw, "https://android.googlesource.com/platform/manifest")
        old, new = ET.fromstring(raw), ET.fromstring(fixed)
        self.assertEqual(count, 1)
        self.assertEqual(new.find("remote").get("fetch"), "https://android.googlesource.com")
        self.assertEqual(old.find("project").attrib, new.find("project").attrib)
        self.assertEqual(prepare.portable_manifest(fixed, "https://android.googlesource.com/platform/manifest")[0], fixed)

    def test_wrong_branch_rejected(self):
        with self.assertRaises(ValueError):
            prepare.portable_manifest(b'<manifest><default revision="main"/></manifest>', "https://example.com/manifest")

    def test_floating_revision_rejected(self):
        with self.assertRaises(ValueError):
            prepare.portable_manifest(b'<manifest><default revision="android17-release"/><project name="a" revision="main"/></manifest>', "https://example.com/manifest")

    def test_file_origin_rejected(self):
        with self.assertRaises(ValueError):
            prepare.portable_manifest(b'<manifest><default revision="android17-release"/><project name="a" revision="' + b'a' * 40 + b'"/></manifest>', "file:///tmp/manifest")

    def test_non_https_fetch_rejected(self):
        with self.assertRaises(ValueError):
            prepare.portable_manifest(b'<manifest><remote name="a" fetch="file:///tmp"/><default revision="android17-release"/><project name="a" revision="' + b'a' * 40 + b'"/></manifest>', "https://example.com/manifest")


if __name__ == "__main__":
    unittest.main()
