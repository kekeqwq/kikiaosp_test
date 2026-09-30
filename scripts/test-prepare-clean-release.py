#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Isolated tests of manifest portability; no repo checkout/network changes."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
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


class IndexRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kiki-index-recovery-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.gitdir = self.root / ".repo/projects/example.git"
        self.worktree = self.root / "example"
        self.gitdir.parent.mkdir(parents=True)
        self.worktree.mkdir()
        self.env = os.environ.copy()
        self.env.pop("GIT_INDEX_FILE", None)
        self.git("init", "--separate-git-dir", str(self.gitdir))
        (self.worktree / "source.txt").write_text("original pinned source\n")
        self.git("add", "source.txt")
        self.git("-c", "user.name=Test", "-c", "user.email=test@localhost", "commit", "-m", "fixture")
        self.commit = self.git("rev-parse", "HEAD").decode().strip()
        self.xml = ('<manifest><project name="example" path="example" revision="' + self.commit + '"/></manifest>').encode()

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.worktree, env=self.env, stderr=subprocess.DEVNULL)

    def test_missing_clean_index_recovers_without_file_write(self):
        original = (self.worktree / "source.txt").stat()
        (self.gitdir / "index").unlink()
        self.assertEqual(prepare.repair_missing_indexes(self.root, self.xml, self.env), 1)
        current = (self.worktree / "source.txt").stat()
        self.assertEqual((original.st_ino, original.st_mtime_ns), (current.st_ino, current.st_mtime_ns))
        self.assertEqual(self.git("status", "--porcelain"), b"")

    def test_existing_index_is_not_touched(self):
        before = (self.gitdir / "index").read_bytes()
        self.assertEqual(prepare.repair_missing_indexes(self.root, self.xml, self.env), 0)
        self.assertEqual((self.gitdir / "index").read_bytes(), before)

    def test_real_edits_are_not_overwritten_or_adopted(self):
        (self.gitdir / "index").unlink()
        (self.worktree / "source.txt").write_text("real modification\n")
        with self.assertRaises(ValueError):
            prepare.repair_missing_indexes(self.root, self.xml, self.env)
        self.assertFalse((self.gitdir / "index").exists())
        self.assertEqual((self.worktree / "source.txt").read_text(), "real modification\n")

    def test_untracked_files_block_recovery(self):
        (self.gitdir / "index").unlink()
        (self.worktree / "unknown.txt").write_text("do not discard")
        with self.assertRaises(ValueError):
            prepare.repair_missing_indexes(self.root, self.xml, self.env)
        self.assertFalse((self.gitdir / "index").exists())

    def test_wrong_pin_blocks_recovery(self):
        (self.gitdir / "index").unlink()
        with self.assertRaises(ValueError):
            prepare.repair_missing_indexes(self.root, self.xml.replace(self.commit.encode(), b"a" * 40), self.env)
        self.assertFalse((self.gitdir / "index").exists())


if __name__ == "__main__":
    unittest.main()
