#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build frozen release inputs in a NEW output tree; never import dev images.

Source preparation must have finished its upstream commit/cleanliness audits.
This builds candidate inputs, not a published package or acceptance claim.
The frozen device/kernel worktrees and audit record survive a build failure.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET


def run(command, cwd, env=None, capture=False):
    print("RUN:", " ".join(map(str, command)), flush=True)
    result = subprocess.run(list(map(str, command)), cwd=cwd, env=env,
                            check=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout if capture else None


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def commits(xml):
    result = {}
    for project in ET.fromstring(xml).findall("project"):
        path, commit = project.get("path", project.get("name")), project.get("revision", "")
        if not path or path.startswith("/") or any(part in ("", ".", "..") for part in path.split("/")) or path in result or not re.fullmatch("[0-9a-f]{40}", commit):
            raise ValueError("Every upstream project must have a unique safe path and full pinned commit.")
        result[path] = commit
    if not 1 <= len(result) <= 5000:
        raise ValueError("Invalid upstream project count.")
    return result


def clean(repository):
    if run(["git", "status", "--porcelain", "--untracked-files=no"], repository, capture=True).strip():
        raise ValueError(f"Tracked source/index changes in {repository}; refusing to freeze.")


def build_environment(out):
    env = os.environ.copy()
    for key in ("OUT_DIR_COMMON_BASE", "OUT_DIR", "TARGET_PRODUCT", "TARGET_BUILD_VARIANT", "TARGET_RELEASE",
                "SISO_CONFIG_DIR", "USE_RBE", "USE_REWRAPPER", "RBE_instance", "RBE_service"):
        env.pop(key, None)
    # Relative logical out is important: multiple Android 17 modules reject
    # generated absolute paths outside TOP. physical out remains independent.
    env.update(OUT_DIR=str(out), BUILD_NUMBER="KIKI_0.3.1_ALPHA", BUILD_USERNAME="KikiEmu",
               BUILD_HOSTNAME="release-builder", SOONG_NINJA="ninja", USE_RBE="false", USE_REWRAPPER="false")
    return env


def logical_output(aosp, out):
    alias = aosp / "out"
    if os.path.lexists(alias):
        if not alias.is_symlink() or alias.resolve(strict=True) != out:
            raise ValueError("Fresh source out must be absent or link to this exact independent release output.")
    else:
        alias.symlink_to(out, target_is_directory=True)
    return Path("out")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preparation", required=True, type=Path)
    parser.add_argument("--kernel-repo", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--record", required=True, type=Path)
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()
    device = Path(__file__).resolve().parent.parent
    preparation = args.preparation.resolve(strict=True)
    source = json.loads((preparation / "prepare.json").read_text())
    if source.get("status") != "clean-pinned-upstream-ready-not-built" or source.get("branch") != "android17-release":
        raise ValueError("Source preparation is not complete. Do not build a partial checkout.")
    aosp = Path(source["checkout"]).resolve(strict=True)
    baseline = Path(source["baseline"]).resolve(strict=True)
    out, record = args.output.resolve(), args.record.resolve()
    kernel = args.kernel_repo.resolve(strict=True)
    if not 1 <= args.jobs <= 16:
        raise ValueError("Use 1..16 explicit build jobs.")
    for target in (out, record):
        if any(target == root or root in target.parents or target in root.parents
               for root in (aosp, baseline, kernel)):
            raise ValueError("Output/audit paths must not overlap source/baseline/kernel trees.")
    if out == record or out in record.parents or record in out.parents:
        raise ValueError("Use distinct output and audit directories.")
    launcher = aosp / ".repo/repo/repo"
    frozen = (preparation / "manifest-repo/default.xml").read_bytes()
    if digest(preparation / "manifest-repo/default.xml") != source["manifestSha256"]:
        raise ValueError("Frozen upstream manifest changed.")
    actual = run([launcher, "manifest", "-r"], aosp, capture=True)
    if commits(actual) != commits(frozen):
        raise ValueError("Upstream commits differ from frozen preparation.")
    clean(device)
    clean(kernel)
    device_commit = run(["git", "rev-parse", "HEAD"], device, capture=True).decode().strip()
    kernel_commit = run(["git", "rev-parse", "HEAD"], kernel, capture=True).decode().strip()
    stamp = record / "build-audit.json"
    runner_commit = device_commit
    if args.resume:
        # Resume builds the already-frozen sources, not the caller's latest
        # branch. Pipeline-only repairs may run from a newer clean commit;
        # both immutable source worktrees are still checked below.
        audit = json.loads(stamp.read_text())
        device_commit, kernel_commit = audit["deviceCommit"], audit["kernelCommit"]
        if any(not re.fullmatch("[0-9a-f]{40}", commit) for commit in (device_commit, kernel_commit)):
            raise ValueError("Invalid frozen source commits in resume record.")
    expected = {"recipe": "kikiaosp-release-v1", "deviceCommit": device_commit,
                "kernelCommit": kernel_commit, "manifestSha256": source["manifestSha256"],
                "aosp": str(aosp), "output": str(out), "product": "kikiaosp_test_arm64_phone_release",
                "systemVersion": "0.3.1-alpha", "sharedInputs": source.get("sharedInputs", "Git objects only; no development outputs/images")}
    if args.resume:
        if any(audit.get(key) != value for key, value in expected.items()):
            raise ValueError("Resume must use the SAME frozen commits, paths and recipe.")
        if audit["phase"] == "applying-integration":
            raise ValueError("Interrupted integration must be audited/recovered explicitly; no blind reapplication.")
    else:
        if out.exists() or record.exists():
            raise ValueError("Output and record must be NEW. Never clean/reuse a development output.")
        if shutil.disk_usage(out.parent).free < 200 * 1024**3:
            raise ValueError("At least 200 GiB free is required before this independent full build.")
        dirty = run([launcher, "forall", "-c", "git status --porcelain --untracked-files=normal"], aosp, capture=True)
        if dirty.strip():
            raise ValueError("Upstream checkout is dirty before integration.")
        record.mkdir(parents=True)
        out.mkdir()
        run(["git", "worktree", "add", "--detach", record / "device-source", device_commit], device)
        run(["git", "worktree", "add", "--detach", record / "kernel-source", kernel_commit], kernel)
        audit = dict(expected, phase="upstream-clean-audited", upstreamProjectCount=len(commits(actual)))
        stamp.write_text(json.dumps(audit, indent=2) + "\n")
    snapshot = record / "device-source"
    kernel_snapshot = record / "kernel-source"
    for path, commit in ((snapshot, device_commit), (kernel_snapshot, kernel_commit)):
        clean(path)
        if run(["git", "rev-parse", "HEAD"], path, capture=True).decode().strip() != commit:
            raise ValueError("Frozen recipe worktree identity changed.")

    def phase(value):
        audit["phase"] = value
        stamp.write_text(json.dumps(audit, indent=2) + "\n")

    if audit["phase"] == "upstream-clean-audited":
        phase("applying-integration")
        run(["bash", snapshot / "scripts/apply-aosp-integration.sh", aosp], snapshot)
        phase("integration-applied")
    run(["bash", snapshot / "scripts/audit-device-tree-profile.sh", snapshot], snapshot)
    run(["bash", snapshot / "scripts/audit-aosp-integration.sh", aosp], snapshot)
    if audit["phase"] == "integration-applied":
        phase("rebuilding-kernel")
    if audit["phase"] == "rebuilding-kernel":
        # Standard pure flake and pinned lock, but force a new derivation
        # execution rather than importing the old developer's kernel file.
        run(["nix", "build", "--rebuild", "--no-update-lock-file", "--out-link", record / "kernel-result"], kernel_snapshot)
        audit["kernelImageSha256"] = digest(record / "kernel-result/boot/kernel")
        audit["flakeLockSha256"] = digest(kernel_snapshot / "flake.lock")
        phase("building-aosp")
    env = build_environment(logical_output(aosp, out))
    audit["pipelineCommit"] = runner_commit
    audit["logicalOutput"] = "out"
    audit["buildBackend"] = "ninja"
    stamp.write_text(json.dumps(audit, indent=2) + "\n")
    if audit["phase"] == "building-aosp":
        build = f"set -eo pipefail; source build/envsetup.sh; lunch kikiaosp_test_arm64_phone_release-cp2a-userdebug; m -j{args.jobs} systemimage vendorimage ramdisk mkbootfs mkbootimg simg2img fsck.erofs"
        run(["bash", "-c", build], aosp, env)
        phase("building-boot-payload")
    if audit["phase"] == "building-boot-payload":
        run(["python", snapshot / "scripts/build-boot-payload.py", "--aosp", aosp,
             "--kernel", record / "kernel-result/boot/kernel", "--output", record / "boot-payload",
             "--fstab", snapshot / "device/kiki/kikiaosp_test/fstab.gpt.ranchu"], snapshot, env)
        phase("checking-release-inputs")
    if audit["phase"] == "checking-release-inputs":
        product = out / "target/product/kikiaosp_test"
        props = {}
        for path in (product / "system/etc/build.prop", product / "system/build.prop"):
            if path.is_file():
                for line in path.read_text().splitlines():
                    if line and not line.startswith("#") and "=" in line:
                        key, value = line.split("=", 1)
                        props[key] = value
        for key, value in {"ro.kikiaosp.build_channel": "release", "ro.kikiaosp.system_version": "0.3.1-alpha",
                           "ro.build.display.id": "KikiAOSP-0.3.1-Alpha",
                           "ro.build.fingerprint": "KikiAOSP/kikiaosp_test/kikiaosp_test:17/CP2A.260605.016/KIKI_0.3.1_ALPHA:userdebug/test-keys"}.items():
            if props.get(key) != value:
                raise ValueError(f"Actual built release property mismatch: {key}={props.get(key)}")
        audit["verifiedProperties"] = {key: value for key, value in props.items() if key.startswith("ro.kikiaosp.") or key in ("ro.build.display.id", "ro.build.fingerprint")}
        vendor_props = {}
        for path in (product / "vendor/etc/build.prop", product / "vendor/build.prop"):
            if path.is_file():
                for line in path.read_text().splitlines():
                    if line and not line.startswith("#") and "=" in line:
                        key, value = line.split("=", 1)
                        vendor_props[key] = value
        if vendor_props.get("ro.vendor.audio.kiki.synchronous_pcm") != "true":
            raise ValueError("Built vendor image did not enable Kiki synchronous PCM.")
        audit["verifiedVendorProperties"] = {"ro.vendor.audio.kiki.synchronous_pcm": "true"}
        audit["images"] = {name: {"bytes": (product / name).stat().st_size, "sha256": digest(product / name)} for name in ("system.img", "vendor.img")}
        phase("clean-candidate-inputs-built-not-packaged-or-accepted")
    print("RELEASE_BUILD_INPUTS_READY", json.dumps(audit), flush=True)


if __name__ == "__main__":
    main()
