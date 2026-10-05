#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Produce a format-1 candidate ONLY from finished, audited clean build inputs.

No development disk, fixture userdata or arbitrary image inputs. Native rc6
kernel reuse may retain the exact hash-pinned prior audited release kernel
receipt after Nix GC/rebuild; it never imports that release's system/userdata.
The output is NEW; generating/validating a ZIP is not boot/user acceptance.
Requires python-jsonschema and the matching AOSP host filesystem tools.
"""
import argparse
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


validator = load_module("format_validator", "system-package.py")
builder = load_module("clean_builder", "build-clean-release.py")
CONTRACT_REVISION = "5cfd0a94c1b267661d2ae96bdc3875365ad686cf"
CONTRACT_HASHES = {
    "manifest.schema.json": "beca6d7e4994881da3f057d11e54213ba600de67fc88cd01af3cb6f9edeaed25",
    "source-lock.schema.json": "023557c5bde711ef6721f7637f6316ca2f84fef983449c1212aa20c088232953",
}
FINISHED_PHASE = "clean-candidate-inputs-built-not-packaged-or-accepted"
VERSION = "0.3.0-alpha"
MODEL = "KikiAOSP 0.3 Alpha"
FINGERPRINT = "KikiAOSP/kikiaosp_test/kikiaosp_test:17/CP2A.260605.016/KIKI_0.3.0_ALPHA:userdebug/test-keys"
KERNEL_VERSION = "7.3.0-rc6-4k"
RELEASE_PROPERTIES = {
    "ro.kikiaosp.build_channel": "release", "ro.kikiaosp.system_version": VERSION,
    "ro.build.display.id": "KikiAOSP-0.3-Alpha", "ro.build.fingerprint": FINGERPRINT,
}
LICENSE_LIMIT = 4194304


def document(path):
    if path.stat().st_size > 8 << 20:
        raise ValueError(f"Oversized audit document: {path.name}")
    return validator.document(path.read_bytes())


def file_record(path, member=None):
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"A regular immutable input is required: {path}")
    result = {"bytes": path.stat().st_size, "sha256": builder.digest(path)}
    if member:
        result = dict(path=member, **result)
    return result


def verify_record(path, expected):
    actual = file_record(path)
    if actual != {key: expected.get(key) for key in ("bytes", "sha256")}:
        raise ValueError(f"Built input changed or is not recorded: {path.name}")


def git_identity(path, expected):
    if not re.fullmatch("[0-9a-f]{40}", expected):
        raise ValueError("A frozen full commit is required.")
    builder.clean(path)
    if builder.run(["git", "rev-parse", "HEAD"], path, capture=True).decode().strip() != expected:
        raise ValueError("Frozen source worktree no longer has the recorded commit.")


def audit_inputs(preparation, record):
    source, audit = document(preparation / "prepare.json"), document(record / "build-audit.json")
    if (source.get("status") != "clean-pinned-upstream-ready-not-built" or source.get("branch") != "android17-release"
            or audit.get("phase") != FINISHED_PHASE or audit.get("recipe") != "kikiaosp-release-v1"
            or audit.get("systemVersion") != VERSION or audit.get("product") != "kikiaosp_test_arm64_phone_release"):
        raise ValueError("Only finished clean release-target inputs can be packaged; no incomplete/dev/fixture fallback.")
    aosp, out = Path(audit["aosp"]).resolve(strict=True), Path(audit["output"]).resolve(strict=True)
    baseline = Path(source["baseline"]).resolve(strict=True)
    if aosp != Path(source["checkout"]).resolve(strict=True) or any(
            left == right or left in right.parents or right in left.parents
            for left, right in ((aosp, baseline), (out, aosp), (out, baseline), (out, record))):
        raise ValueError("Source/output/audit are not the recorded independent release trees.")
    raw = (preparation / "manifest-repo/default.xml").read_bytes()
    raw_hash = hashlib.sha256(raw).hexdigest()
    if raw_hash != source["manifestSha256"] or raw_hash != audit["manifestSha256"]:
        raise ValueError("Frozen manifest hash changed.")
    pins = builder.commits(raw)
    if len(pins) != source["projectCount"] or len(pins) != audit["upstreamProjectCount"]:
        raise ValueError("Frozen upstream project counts do not match.")
    actual = builder.run([aosp / ".repo/repo/repo", "manifest", "-r"], aosp, capture=True)
    if builder.commits(actual) != pins:
        raise ValueError("Actual upstream project commits drifted after the build.")
    device, kernel = record / "device-source", record / "kernel-source"
    git_identity(device, audit["deviceCommit"])
    git_identity(kernel, audit["kernelCommit"])
    builder.run(["bash", device / "scripts/audit-device-tree-profile.sh", device], device)
    builder.run(["bash", device / "scripts/audit-aosp-integration.sh", aosp], device)
    # Also check the ENTIRE integrated device directory, not only the profile
    # sentinel strings. No new/untracked device file can join this payload.
    subtree = "device/kiki/kikiaosp_test"
    files = builder.run(["git", "ls-files", "-z", "--", subtree], device, capture=True).split(b"\0")
    names = {os.fsdecode(name) for name in files if name}
    actual_names = {path.relative_to(aosp).as_posix() for path in (aosp / subtree).rglob("*") if path.is_file() or path.is_symlink()}
    if actual_names != names:
        raise ValueError("Integrated device contains missing or unexpected files.")
    # Native Android kernel/target-files target uses an explicit generated
    # dependency, never secret or untracked files in the device overlay.
    if (device / 'device/kiki/kikiaosp_test/ota/product.mk').exists():
        native_inputs = load_module('native_generated_inputs', 'prepare-native-build-inputs.py')
        native_inputs.verify(aosp, record)
    for name in sorted(names):
        if file_record(aosp / name) != file_record(device / name):
            raise ValueError(f"Integrated device differs from its frozen source: {name}")
    for key, expected in RELEASE_PROPERTIES.items():
        if audit.get("verifiedProperties", {}).get(key) != expected:
            raise ValueError(f"Release build did not record the required property: {key}")
    product, tools = out / "target/product/kikiaosp_test", out / "host/linux-x86/bin"
    if audit.get("verifiedVendorProperties", {}).get("ro.vendor.audio.kiki.synchronous_pcm") != "true":
        raise ValueError("Release build did not record synchronous PCM vendor policy.")
    for name in ("system.img", "vendor.img"):
        verify_record(product / name, audit.get("images", {}).get(name, {}))
    boot_recipe = document(record / "boot-payload/boot-recipe.json")
    if (boot_recipe.get("recipeVersion") != 1 or boot_recipe.get("deviceCommit") != audit["deviceCommit"]
            or boot_recipe.get("bootHeaderVersion") != 4 or boot_recipe.get("fstabPath") != subtree + "/fstab.gpt.ranchu"):
        raise ValueError("Boot was not generated by the frozen GPT recipe.")
    verify_record(record / "boot-payload/boot.img", boot_recipe["outputs"]["boot.img"])
    verify_record(record / "boot-payload/ramdisk.img", boot_recipe["outputs"]["ramdisk.img"])
    for key, path in {
        "staticInitSha256": product / "ramdisk/init", "kernelSha256": record / "kernel-result/boot/kernel",
        "mkbootfsSha256": tools / "mkbootfs", "mkbootimgSha256": tools / "mkbootimg",
    }.items():
        if file_record(path)["sha256"] != boot_recipe["inputs"].get(key):
            raise ValueError(f"Boot recipe input changed: {key}")
    if (file_record(record / "kernel-result/boot/kernel")["sha256"] != audit["kernelImageSha256"]
            or builder.digest(kernel / "flake.lock") != audit["flakeLockSha256"]
            or builder.digest(device / boot_recipe["fstabPath"]) != boot_recipe["fstabSha256"]):
        raise ValueError("Frozen kernel/fstab provenance does not match the boot recipe.")
    return source, audit, raw, boot_recipe, product, tools


def normalized_derivations(raw):
    value = validator.document(raw)
    return value.get("derivations", value)


def historical_native_rc6_notice(record, kernel_hash, drv, src, live_hash):
    # Nix input-addressed outputs may rebuild to different bytes after GC.
    # Retain the ALREADY BOOT/USER-AUDIO-TESTED kernel, never silently switch
    # it to the replacement Image or claim they are byte reproducible.
    expected_image = "38c6ad1d6cffc76af1f4b6ce66ba42db4d8865b0f60b842fd147bef52b3a5b7c"
    baseline = Path("/home/keke/projects/kikiaosp-package-alpha-0.3-rc6/KikiAOSP-0.3.0-alpha-arm64.zip")
    expected_zip = "3fab8e602ff653cb620a1b9b31358f724ca4444c6b12edfcb94a4e282648e1f3"
    native = record / "device-source/device/kiki/kikiaosp_test/ota/product.mk"
    if kernel_hash != expected_image or drv != "/nix/store/kv6ydvd7v35wak76jq7snngsijkd1dw1-linux-aarch64-unknown-linux-gnu-7.3.0-rc6-kikiaosp.drv" or not native.is_file() or "ro.kiki.ota.layout=gpt-ab-v1" not in native.read_text():
        raise ValueError("Bundled kernel differs from the Nix Linux output; no exact historical native receipt authorized.")
    if builder.digest(baseline) != expected_zip:
        raise ValueError("Historical audited release kernel receipt ZIP changed.")
    with zipfile.ZipFile(baseline) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        lock_bytes = archive.read(manifest["sourceLock"]["path"])
        if hashlib.sha256(lock_bytes).hexdigest() != manifest["sourceLock"]["sha256"]:
            raise ValueError("Historical kernel source-lock receipt changed.")
        lock = json.loads(lock_bytes)
        if lock["kernel"]["imageSha256"] != expected_image or lock["kernel"]["sourceVersion"] != "7.3-rc6" or lock["kernel"]["commit"] != "f8020a4c6da14b98b285da2c3c5f2ab96a772486":
            raise ValueError("Historical kernel built-source receipt changed.")
        boot = next(item for item in manifest["payloads"] if item["role"] == "boot")
        image = archive.read(boot["path"])
        if hashlib.sha256(image).hexdigest() != boot["sha256"] or image[:8] != b"ANDROID!":
            raise ValueError("Historical kernel boot payload changed.")
        length = int.from_bytes(image[8:12], "little")
        if hashlib.sha256(image[4096:4096+length]).hexdigest() != expected_image:
            raise ValueError("Historical kernel bytes do not match the built-source receipt.")
        # License text still comes from the ACTUAL derivation source below.
        return {"baselineArchiveSha256": expected_zip, "historicalBuiltKernelCommit": lock["kernel"]["commit"], "retainedKernelImageSha256": expected_image,
                "restoredLiveNixImageSha256": live_hash, "byteReproducible": False, "reason": "Exact audited rc6 kernel retained after Nix GC; replacement same-derivation output is not byte-identical"}


def kernel_notices(record, kernel_hash):
    # Resolve COPYRIGHT from the ACTUAL pure Nix build graph, not a guessed
    # local source directory or a separately downloaded Linux release.
    bundle = normalized_derivations(builder.run(["nix", "derivation", "show", record / "kernel-result"], record, capture=True))
    if len(bundle) != 1:
        raise ValueError("Ambiguous kernel bundle derivation.")
    top = next(iter(bundle.values()))
    dependencies = top.get("inputDrvs", top.get("inputs", {}).get("drvs", {}))
    candidates = [key for key in dependencies if key.endswith("-linux-aarch64-unknown-linux-gnu-7.3.0-rc6-kikiaosp.drv")]
    if len(candidates) != 1:
        raise ValueError("The kernel bundle lacks the expected pinned Linux derivation.")
    drv = candidates[0]
    drv = drv if drv.startswith("/nix/store/") else "/nix/store/" + drv
    graph = normalized_derivations(builder.run(["nix", "derivation", "show", drv], record, capture=True))
    if len(graph) != 1:
        raise ValueError("Ambiguous Linux derivation.")
    linux = next(iter(graph.values()))
    attrs = linux.get("structuredAttrs", linux.get("env", {}))
    src = Path(attrs.get("src", "")).resolve(strict=True)
    output = Path(linux.get("env", {}).get("out", "")).resolve(strict=True)
    if Path("/nix/store") not in src.parents or Path("/nix/store") not in output.parents:
        raise ValueError("Kernel source/image must belong to the pure Nix derivation.")
    live_hash = file_record(output / "Image")["sha256"]
    historical = None
    if live_hash != kernel_hash:
        historical = historical_native_rc6_notice(record, kernel_hash, drv, src, live_hash)
    modules = record / "kernel-result/modules/lib/modules"
    if sorted(path.name for path in modules.iterdir() if path.is_dir()) != [KERNEL_VERSION]:
        raise ValueError("Actual Nix kernel release differs from the format-1 identity.")
    chunks = []
    for name in ("COPYING", "LICENSES/preferred/GPL-2.0", "LICENSES/exceptions/Linux-syscall-note"):
        path = src / name
        file_record(path)
        chunks.append(("\n===== Linux " + name + " =====\n").encode() + path.read_bytes())
    graph = {"linuxDerivation": drv, "source": str(src)}
    if historical:
        graph["historicalAuditedKernelReceipt"] = historical
    return b"".join(chunks), graph


def raw_erofs(source, target, tools):
    with source.open("rb") as stream:
        header = stream.read(4096)
    if header[:4] == b"\x3a\xff\x26\xed":
        builder.run([tools / "simg2img", source, target], tools)
    elif header[1024:1028] == b"\xe2\xe1\xf5\xe0":
        shutil.copyfile(source, target)
    else:
        raise ValueError("Built filesystem is neither Android sparse nor raw EROFS.")
    size = target.stat().st_size
    with target.open("rb") as stream:
        stream.seek(1024)
        magic = stream.read(4)
    if magic != b"\xe2\xe1\xf5\xe0" or not 4096 <= size <= 16 << 30 or size % 4096:
        raise ValueError("Filesystem conversion did not produce a supported raw EROFS payload.")


def built_file(root, candidates):
    present = [root / name for name in candidates if (root / name).is_file()]
    if len(present) != 1 or present[0].is_symlink() or root not in present[0].resolve().parents:
        raise ValueError(f"Missing/ambiguous/redirected packaged file: {candidates}")
    return present[0]


def properties(path):
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            if key in result:
                raise ValueError("Duplicate generated build property.")
            result[key] = value
    return result


def image_properties(root):
    props = properties(built_file(root, ("system/etc/build.prop", "system/build.prop", "etc/build.prop", "build.prop")))
    for key, expected in RELEASE_PROPERTIES.items():
        if props.get(key) != expected:
            raise ValueError(f"The ACTUAL packaged filesystem has the wrong {key}.")
    if props.get("ro.product.system.model", props.get("ro.product.model")) != MODEL or props.get("ro.build.version.release") != "17":
        raise ValueError("Packaged Android version/model does not match the release identity.")
    return {key: props[key] for key in (*RELEASE_PROPERTIES, "ro.build.version.release")}


def image_vendor_audio_policy(root):
    props = properties(built_file(root, ("vendor/etc/build.prop", "vendor/build.prop", "etc/build.prop", "build.prop")))
    if props.get("ro.vendor.audio.kiki.synchronous_pcm") != "true":
        raise ValueError("Packaged vendor EROFS did not enable synchronous PCM.")
    return {"ro.vendor.audio.kiki.synchronous_pcm": "true"}


def notice_text(path):
    with gzip.open(path, "rb") as stream:
        raw = stream.read((128 << 20) + 1)
    if len(raw) > 128 << 20 or b"<!DOCTYPE" in raw or b"<!ENTITY" in raw:
        raise ValueError("Oversized or externally-defined generated license XML.")
    # Keep the generated notices VERBATIM. Android's generator can emit XML-
    # forbidden characters inside third-party CDATA; reparsing/reformatting
    # would either reject its real output or silently discard license bytes.
    # This is a bounded text attachment, never an XML configuration to execute.
    raw.decode("utf-8")
    if b"<licenses>" not in raw[:256] or not raw.rstrip().endswith(b"</licenses>") or b"<file-content " not in raw:
        raise ValueError("Missing/incomplete generated AOSP license text.")
    return raw


def license_parts(raw, limit=LICENSE_LIMIT):
    if limit < 4:
        raise ValueError("License split limit must accommodate a UTF-8 code point.")
    raw.decode("utf-8")
    result = []
    while raw:
        cut = min(limit, len(raw))
        if cut < len(raw):
            newline = raw.rfind(b"\n", limit // 2, cut)
            if newline != -1:
                cut = newline + 1
            while True:
                try:
                    raw[:cut].decode("utf-8")
                    break
                except UnicodeDecodeError:
                    cut -= 1
                    if not cut:
                        raise ValueError("License split limit is too small for UTF-8.")
        result.append(raw[:cut])
        raw = raw[cut:]
    if not result:
        raise ValueError("Empty license material.")
    return result


def write_zip(path, members):
    with zipfile.ZipFile(path, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
        for name, source in sorted(members.items()):
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.create_system, info.external_attr, info.compress_type = 3, 0o100644 << 16, zipfile.ZIP_DEFLATED
            info.file_size = source.stat().st_size
            with source.open("rb") as stream, archive.open(info, "w", force_zip64=info.file_size >= 1 << 31) as output:
                shutil.copyfileobj(stream, output, length=1048576)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preparation", type=Path, required=True)
    parser.add_argument("--build-record", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    builder.clean(repo)
    pipeline_commit = builder.run(["git", "rev-parse", "HEAD"], repo, capture=True).decode().strip()
    for name, expected in CONTRACT_HASHES.items():
        if builder.digest(validator.CONTRACT / name) != expected:
            raise ValueError("The frozen producer/consumer contract changed; no unilateral schema rewrite.")
    preparation, record = args.preparation.resolve(strict=True), args.build_record.resolve(strict=True)
    source, audit, raw, boot_recipe, product, tools = audit_inputs(preparation, record)
    output = args.output.resolve()
    if os.path.lexists(output) or any(output == root or root in output.parents or output in root.parents
                                    for root in (Path(audit["aosp"]), Path(audit["output"]), record, preparation, repo)):
        raise ValueError("Packaging output must be NEW and outside source/build/audit trees.")
    for name in ("mkfs.erofs", "fsck.erofs", "mkbootfs", "mkbootimg"):
        file_record(tools / name)
    required = 6 * sum(entry["bytes"] for entry in audit["images"].values()) + (1 << 30)
    if shutil.disk_usage(output.parent).free < required:
        raise ValueError("Insufficient space for raw EROFS verification and a new ZIP.")
    kernel_text, kernel_graph = kernel_notices(record, audit["kernelImageSha256"])
    output.mkdir()
    package = output / f"KikiAOSP-{VERSION}-arm64.zip"
    with tempfile.TemporaryDirectory(prefix=".owned-package-staging-", dir=output) as temporary:
        stage = Path(temporary)
        members = {}
        for name in ("payload", "licenses", "provenance"):
            (stage / name).mkdir()
        shutil.copyfile(record / "boot-payload/boot.img", stage / "payload/boot.img")
        notices = []
        for role in ("system", "vendor"):
            raw_erofs(product / f"{role}.img", stage / f"payload/{role}.img", tools)
            extracted = stage / f"check-{role}"
            extracted.mkdir()
            # Check ALL file encodings while extracting only to a new owned
            # stage. No --force/overwrite/preserve or developer filesystem tool.
            builder.run([tools / "fsck.erofs", "--no-preserve", f"--extract={extracted}", stage / f"payload/{role}.img"], tools)
            if role == "system":
                verified_props = image_properties(extracted)
            else:
                image_vendor_audio_policy(extracted)
            mandatory = built_file(extracted, ("system/etc/NOTICE.xml.gz", "etc/NOTICE.xml.gz"))
            paths = sorted({mandatory, *extracted.rglob("NOTICE.xml.gz")})
            if len(paths) > 32:
                raise ValueError("Unexpectedly many generated notices.")
            for path in paths:
                if path.is_symlink() or extracted not in path.resolve().parents:
                    raise ValueError("Redirected image notice.")
                notices.append((f"\n===== Packaged {role}/{path.relative_to(extracted)} =====\n").encode() + notice_text(path))
        for index, part in enumerate(license_parts(b"".join(notices)), 1):
            name = "aosp.txt" if index == 1 else f"aosp-{index:02}.txt"
            (stage / "licenses" / name).write_bytes(part)
        (stage / "licenses/kernel.txt").write_bytes(kernel_text)
        # GPL terms accompany our SPDX GPL-2.0-or-later build/packaging code.
        # Older frozen device revisions predate the root license attachment;
        # do not invent a newer built device commit to attach standard terms.
        builder.run(["git", "ls-files", "--error-unmatch", "LICENSE"], repo)
        file_record(repo / "LICENSE")
        (stage / "licenses/kikiaosp.txt").write_bytes((repo / "LICENSE").read_bytes())
        (stage / "licenses/sources.txt").write_text(
            "KikiAOSP source identities\n\nAOSP: https://android.googlesource.com/platform/manifest\n"
            "Exact per-project commits: provenance/source-lock.json manifestXml\n"
            f"Device/patch/build recipe: https://github.com/kekeqwq/kikiaosp_test/tree/{audit['deviceCommit']}\n"
            f"Kernel flake/config/patches: https://github.com/kekeqwq/kikiaosp_kernel/tree/{audit['kernelCommit']}\n"
            f"Package recipe and GPL terms: https://github.com/kekeqwq/kikiaosp_test/tree/{pipeline_commit}\n"
            "GPL-2.0-or-later applies to files so marked; e.g. camera source retains its Apache-2.0 SPDX license.\n"
            "Third-party code retains its original licenses. Public release still requires the corresponding-source/license audit.\n",
            encoding="utf-8")
        lock = {
            "sourceLockVersion": 1,
            "contract": {"repository": "https://github.com/kekeqwq/kikiaosp_test", "revision": CONTRACT_REVISION,
                         "manifestSchemaSha256": CONTRACT_HASHES["manifest.schema.json"],
                         "sourceLockSchemaSha256": CONTRACT_HASHES["source-lock.schema.json"]},
            "aosp": {"branch": "android17-release", "manifestXml": raw.decode("utf-8"),
                     "manifestSha256": audit["manifestSha256"], "projectCount": source["projectCount"]},
            "device": {"repository": "https://github.com/kekeqwq/kikiaosp_test", "commit": audit["deviceCommit"]},
            "kernel": {"repository": "https://github.com/kekeqwq/kikiaosp_kernel", "commit": audit["kernelCommit"],
                       "flakeLockSha256": audit["flakeLockSha256"], "sourceVersion": "7.3-rc6", "imageSha256": audit["kernelImageSha256"]},
            "build": {"cleanSource": True, "independentOutput": True, "outputRecipe": "kikiaosp-release-v1",
                      "tools": {"mkbootfsSha256": boot_recipe["inputs"]["mkbootfsSha256"],
                                "mkbootimgSha256": boot_recipe["inputs"]["mkbootimgSha256"],
                                "mkfsErofsSha256": builder.digest(tools / "mkfs.erofs")}},
        }
        validator.validate_lock(lock)
        (stage / "provenance/source-lock.json").write_text(json.dumps(lock, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        payloads = []
        for role in ("boot", "system", "vendor"):
            path = f"payload/{role}.img"
            entry = file_record(stage / path, path)
            entry.update(role=role, imageFormat="android-boot-v4" if role == "boot" else "raw-erofs",
                         partitionBytes=(entry["bytes"] + validator.ALIGN - 1) // validator.ALIGN * validator.ALIGN)
            payloads.append(entry)
        licenses = [file_record(path, "licenses/" + path.name) for path in sorted((stage / "licenses").iterdir())]
        manifest = {
            "kind": "org.kiki.kikiaosp.system", "formatVersion": 1, "systemVersion": VERSION,
            "product": "kikiaosp_test", "channel": "release", "architecture": "aarch64", "pageSizeBytes": 4096,
            "runtimeAbi": "kiki-arm64-whpx-virgl-gpt-v1", "minimumLauncherVersion": "0.1.0-alpha",
            "layoutVersion": "gpt-v1", "sectorSizeBytes": 512, "alignmentBytes": 1048576, "minimumDataBytes": 8 << 30,
            "payloads": payloads, "sourceLock": file_record(stage / "provenance/source-lock.json", "provenance/source-lock.json"),
            "licenses": licenses, "buildIdentity": {"displayVersion": MODEL, "model": MODEL, "fingerprint": FINGERPRINT,
                                                   "androidVersion": "17", "kernelVersion": KERNEL_VERSION},
            "requiredFeatures": ["boot-v4-direct", "gpt-v1", "fresh-f2fs", "exact-total-storage", "sdl-native-pixels",
                                 "virgl", "guest-120hz", "instance-isolation-v1", "surface-camera-v1"],
        }
        declared = validator.validate_manifest(manifest)
        (stage / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        members = {name: stage / name for name in declared}
        write_zip(package, members)
        try:
            validator.validate_package(package)
        except Exception:
            package.unlink()  # Only this script's CREATE_NEW candidate.
            raise
    package_hash = builder.digest(package)
    (output / (package.name + ".sha256")).write_text(f"{package_hash}  {package.name}\n", encoding="ascii")
    report = {"status": "format-1-candidate-generated-not-boot-tested-or-publicly-accepted", "systemVersion": VERSION,
              "package": file_record(package, package.name), "packagingCommit": pipeline_commit,
              "buildAuditSha256": builder.digest(record / "build-audit.json"), "deviceCommit": audit["deviceCommit"],
              "kernelCommit": audit["kernelCommit"], "kernelGraph": kernel_graph, "verifiedImageProperties": verified_props,
              "fsckErofsSha256": builder.digest(tools / "fsck.erofs"), "archiveMembers": sorted(members)}
    # Private local audit (Nix paths) is NOT a ZIP member/public release asset.
    (output / "package-audit.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("CANDIDATE_PACKAGE_VALIDATED_NOT_ACCEPTED", package, package_hash, flush=True)


if __name__ == "__main__":
    main()
