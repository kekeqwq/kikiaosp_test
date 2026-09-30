#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Safety guards only; no actual Git/Nix/build jobs or release claims."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release_build", Path(__file__).with_name("build-clean-release.py"))
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class Guards(unittest.TestCase):
    def test_independent_local_backend_is_explicit(self):
        with patch.dict("os.environ", {"OUT_DIR": "/old/development/out", "TARGET_PRODUCT": "wrong",
                                       "SOONG_NINJA": "siso", "SISO_CONFIG_DIR": "/foreign", "USE_RBE": "true"}):
            env = build.build_environment(Path("/fresh/release-output"))
        self.assertEqual(env["OUT_DIR"], "/fresh/release-output")
        self.assertEqual(env["SOONG_NINJA"], "ninja")
        self.assertEqual(env["USE_RBE"], "false")
        self.assertNotIn("TARGET_PRODUCT", env)
        self.assertNotIn("SISO_CONFIG_DIR", env)

    def test_logical_out_uses_only_exact_independent_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            aosp, out, other = root / "fresh-source", root / "fresh-output", root / "foreign-output"
            for path in (aosp, out, other):
                path.mkdir()
            self.assertEqual(build.logical_output(aosp, out), Path("out"))
            self.assertEqual((aosp / "out").resolve(), out)
            self.assertEqual(build.logical_output(aosp, out), Path("out"))
            with self.assertRaises(ValueError):
                build.logical_output(aosp, other)
            (aosp / "out").unlink()
            (aosp / "out").mkdir()
            with self.assertRaises(ValueError):
                build.logical_output(aosp, out)

    def test_commits_exact(self):
        self.assertEqual(build.commits('<manifest><project name="platform/example" path="external/example" revision="' + 'a' * 40 + '"/></manifest>'), {"external/example": 'a' * 40})

    def test_floating_rejected(self):
        with self.assertRaises(ValueError):
            build.commits('<manifest><project name="example" revision="main"/></manifest>')

    def test_duplicate_path_rejected(self):
        project = '<project name="example" revision="' + 'a' * 40 + '"/>'
        with self.assertRaises(ValueError):
            build.commits('<manifest>' + project + project + '</manifest>')

    def test_unsafe_path_rejected(self):
        for path in ("/outside", "../outside", "a/../outside", "a//b"):
            with self.assertRaises(ValueError):
                build.commits('<manifest><project name="example" path="' + path + '" revision="' + 'a' * 40 + '"/></manifest>')

    def test_empty_manifest_rejected(self):
        with self.assertRaises(ValueError):
            build.commits('<manifest/>')

    def test_incomplete_source_never_starts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "prepare.json").write_text(json.dumps({"status": "preparing-source-not-built", "branch": "android17-release"}))
            with patch("sys.argv", ["build", "--preparation", directory, "--kernel-repo", directory, "--output", str(root / "out"), "--record", str(root / "record")]), patch.object(build, "run") as run:
                with self.assertRaises(ValueError):
                    build.main()
                run.assert_not_called()
                self.assertFalse((root / "out").exists())

    def test_dirty_source_rejected(self):
        with patch.object(build, "run", return_value=b" M device.mk\n"):
            with self.assertRaises(ValueError):
                build.clean(Path("/unused-fixture"))


if __name__ == "__main__":
    unittest.main()
