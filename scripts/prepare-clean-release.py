#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Prepare an independent checkout from the baseline's exact project commits.

Only Git object caches are shared via repo --reference. No patched worktree
files, out/, development images, initialized disks or backup volumes are copied.
Run in tmux; this script does not build or publish a release.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from urllib.parse import urljoin, urlparse


def run(args, cwd, env, capture=False):
    print("RUN:", " ".join(str(item) for item in args), flush=True)
    return subprocess.run([str(item) for item in args], cwd=cwd, env=env, check=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def portable_manifest(raw, origin):
    """Freeze revisions without changing where relative remotes are fetched.

    repo resolves fetch relative to the ORIGINAL manifest repository URL, not
    its filesystem checkout. Exporting to a file:// manifest needs absolute
    fetch URLs; this changes no project commit, path or build input.
    """
    root = ET.fromstring(raw)
    default = root.find("default")
    projects = root.findall("project")
    if (root.tag != "manifest" or default is None or
            default.get("revision") != "android17-release" or not projects or
            any(not re.fullmatch(r"[0-9a-f]{40}", item.get("revision", "")) for item in projects)):
        raise ValueError("Expected android17-release with fully pinned project commits.")
    if urlparse(origin).scheme != "https":
        raise ValueError("The original manifest must use an explicit HTTPS upstream.")
    for remote in root.findall("remote"):
        # Matches repo's _resolveFetchUrl: neither URL gains a trailing slash.
        resolved = urljoin(origin.rstrip("/"), remote.get("fetch", "").rstrip("/"))
        if urlparse(resolved).scheme != "https" or not urlparse(resolved).hostname:
            raise ValueError("Frozen upstream remotes must use absolute HTTPS URLs.")
        remote.set("fetch", resolved.rstrip("/"))
    return ET.tostring(root, encoding="utf-8", xml_declaration=True), len(projects)


def commit_manifest(manifest_repo, env):
    run(["git", "add", "default.xml"], manifest_repo, env)
    run(["git", "-c", "user.name=KikiAOSP Release Builder", "-c", "user.email=release@localhost",
         "commit", "-m", "Freeze exact AOSP commits with portable upstream remotes"], manifest_repo, env)


def seed_reference_boundaries(base, checkout, raw):
    """Share cache metadata, never source/output files or mutable refs.

    repo --reference shares the object database but does not inherit the
    per-worktree shallow cutoffs. Without those cutoffs git tries missing
    parents during negotiation and may fetch an unnecessary full history.
    Only initialized NEW project gitdirs borrowing THIS baseline are eligible.
    """
    count = 0
    for item in ET.fromstring(raw).findall("project"):
        path, name = item.get("path", item.get("name")), item.get("name")
        if any(not value or value.startswith("/") or ".." in Path(value).parts for value in (path, name)):
            raise ValueError("Unsafe pinned project path.")
        old = base / ".repo/projects" / (path + ".git") / "shallow"
        new = checkout / ".repo/projects" / (path + ".git") / "shallow"
        alternate = checkout / ".repo/project-objects" / (name + ".git") / "objects/info/alternates"
        expected = base / ".repo/project-objects" / (name + ".git") / "objects"
        if not old.is_file() or new.exists() or not (new.parent / "HEAD").is_file() or not alternate.is_file():
            continue
        references = alternate.read_text().splitlines()
        if references != [str(expected)] or new.parent.resolve() == old.parent.resolve():
            raise ValueError("Reference Git cache does not belong to the recorded baseline.")
        cutoffs = old.read_bytes()
        if not cutoffs or any(not re.fullmatch(rb"[0-9a-f]{40}", line) for line in cutoffs.splitlines()):
            raise ValueError("Invalid original shallow-cache metadata.")
        # CREATE_NEW prevents replacement of metadata from a genuine fetch.
        with new.open("xb") as stream:
            stream.write(cutoffs)
        count += 1
    print("SHALLOW_REFERENCE_BOUNDARIES:", count, flush=True)
    return count


def repair_missing_indexes(checkout, raw, env):
    """Repair ONLY absent indexes whose existing files exactly match the pin.

    read-tree without -u never writes worktree files. Use a temporary index to
    verify every tracked/untracked file before CREATE_NEW-linking it into place.
    Existing indexes, source edits, sparse checkouts and foreign gitdirs refuse.
    This is explicit recovery for interrupted NEW repo clients, not git reset.
    """
    count = 0
    metadata_root = checkout / ".repo/projects"
    for item in ET.fromstring(raw).findall("project"):
        path, commit = item.get("path", item.get("name")), item.get("revision", "")
        if (not path or path.startswith("/") or any(part in ("", ".", "..") for part in path.split("/"))
                or not re.fullmatch("[0-9a-f]{40}", commit)):
            raise ValueError("Unsafe/unpinned project in index recovery.")
        gitdir = metadata_root / (path + ".git")
        index = gitdir / "index"
        if os.path.lexists(index):
            continue
        worktree = checkout / path
        actual = subprocess.check_output(["git", "rev-parse", "--absolute-git-dir"], cwd=worktree, env=env).decode().strip()
        if (Path(actual).resolve() != gitdir.resolve() or metadata_root.resolve() not in gitdir.resolve().parents
                or checkout.resolve() not in worktree.resolve().parents):
            raise ValueError("Index recovery may touch only this new client's own project gitdir.")
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=worktree, env=env).decode().strip()
        sparse = subprocess.run(["git", "config", "--bool", "--get", "core.sparseCheckout"],
                                cwd=worktree, env=env, stdout=subprocess.PIPE, check=False)
        if head != commit or sparse.stdout.strip() == b"true":
            raise ValueError("Index recovery requires the exact pinned HEAD and a complete worktree.")
        with tempfile.TemporaryDirectory(prefix=".kiki-index-recovery-", dir=gitdir) as temporary:
            candidate = Path(temporary) / "index"
            isolated = dict(env, GIT_INDEX_FILE=str(candidate))
            subprocess.run(["git", "-c", "core.splitIndex=false", "read-tree", commit],
                           cwd=worktree, env=isolated, check=True)
            dirty = subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=normal"],
                                            cwd=worktree, env=isolated)
            if dirty.strip():
                raise ValueError(f"Files in {path} differ from the pin; refusing missing-index recovery.")
            # link fails if another process created ANY index, including a
            # dangling symlink. Never replace an existing index or worktree.
            os.link(candidate, index)
        count += 1
        print("VERIFIED_MISSING_INDEX_RECOVERED:", path, flush=True)
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--checkout", required=True, type=Path)
    parser.add_argument("--record", required=True, type=Path)
    parser.add_argument("--proxy", required=True)
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--repair-relative-remotes", action="store_true",
                        help="Explicitly migrate an earlier local-manifest preparation; preserve every pinned revision")
    parser.add_argument("--repair-missing-indexes", action="store_true",
                        help="Explicit recovery: rebuild only absent indexes after comparing existing files to each exact pin")
    args = parser.parse_args()
    base = args.baseline.resolve(strict=True)
    checkout = args.checkout.resolve()
    record = args.record.resolve()
    if (base == checkout or base in checkout.parents or checkout in base.parents or
            not (base / ".repo/manifest.xml").is_file() or not 1 <= args.jobs <= 16):
        raise ValueError("Use an independent checkout path and a complete baseline repo client.")
    if (checkout.exists() or record.exists()) and not args.resume:
        raise ValueError("Checkout/record must be NEW; only an explicit --resume may reuse this preparation.")
    env = os.environ.copy()
    for key in ("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY"):
        env[key] = args.proxy
    env["GIT_CONFIG_COUNT"] = "1"
    env["GIT_CONFIG_KEY_0"] = "http.proxy"
    env["GIT_CONFIG_VALUE_0"] = args.proxy
    launcher = base / ".repo/repo/repo"
    if not launcher.is_file():
        raise ValueError("The baseline's pinned repo launcher is missing.")
    if args.repair_relative_remotes and not args.resume:
        raise ValueError("Manifest repair requires --resume.")
    if args.repair_missing_indexes and not args.resume:
        raise ValueError("Index recovery requires an explicit --resume.")
    origin = run(["git", "remote", "get-url", "origin"], base / ".repo/manifests", env, True).decode().strip()
    if not args.resume:
        raw = run([launcher, "manifest", "-r"], base, env, True)
        original_hash = hashlib.sha256(raw).hexdigest()
        raw, count = portable_manifest(raw, origin)
        record.mkdir(parents=True)
        manifest_repo = record / "manifest-repo"
        manifest_repo.mkdir()
        (manifest_repo / "default.xml").write_bytes(raw)
        run(["git", "init", "-b", "release-source"], manifest_repo, env)
        commit_manifest(manifest_repo, env)
        metadata = {"status": "preparing-source-not-built", "branch": "android17-release",
                    "manifestSha256": hashlib.sha256(raw).hexdigest(), "projectCount": count,
                    "originalManifestSha256": original_hash, "originalManifestOrigin": origin,
                    "baseline": str(base), "checkout": str(checkout), "sharedInputs": "Git object cache only, no worktree/out/images",
                    "repoToolCommit": run(["git", "rev-parse", "HEAD"], base / ".repo/repo", env, True).decode().strip()}
        (record / "prepare.json").write_text(json.dumps(metadata, indent=2) + "\n")
        checkout.mkdir(parents=True)
        run([launcher, "init", "-u", manifest_repo.as_uri(), "-b", "release-source", "--reference", base,
             "--depth", "1", "--no-clone-bundle", "--no-use-superproject"], checkout, env)
    else:
        metadata = json.loads((record / "prepare.json").read_text())
        if metadata["baseline"] != str(base) or metadata["checkout"] != str(checkout):
            raise ValueError("Resume identity does not match the original preparation.")
        raw = (record / "manifest-repo/default.xml").read_bytes()
        if hashlib.sha256(raw).hexdigest() != metadata["manifestSha256"]:
            raise ValueError("Frozen manifest changed; resume refused.")
        if args.repair_relative_remotes:
            if metadata["status"] == "clean-pinned-upstream-ready-not-built":
                raise ValueError("Do not rewrite a completed preparation.")
            migrated, count = portable_manifest(raw, origin)
            metadata["originalManifestSha256"] = metadata["manifestSha256"]
            metadata["originalManifestOrigin"] = origin
            metadata["manifestSha256"] = hashlib.sha256(migrated).hexdigest()
            metadata["projectCount"] = count
            (record / "manifest-repo/default.xml").write_bytes(migrated)
            commit_manifest(record / "manifest-repo", env)
            (record / "prepare.json").write_text(json.dumps(metadata, indent=2) + "\n")
            raw = migrated
        # Refresh only the generated manifest checkout; never force/reset an
        # upstream project or touch the developer checkout/output.
        run([launcher, "init", "-u", (record / "manifest-repo").as_uri(), "-b", "release-source",
             "--reference", base, "--depth", "1", "--no-clone-bundle", "--no-use-superproject"], checkout, env)
    seed_reference_boundaries(base, checkout, raw)
    # Local object-cache checkout first. If any required object is genuinely
    # absent, fetch through the explicitly configured proxy, not direct network.
    try:
        run([launcher, "sync", "--local-only", "--fail-fast", "-j", args.jobs], checkout, env)
    except subprocess.CalledProcessError:
        seed_reference_boundaries(base, checkout, raw)
        print("Local object cache incomplete; fetching exact pinned revisions through proxy.", flush=True)
        # Do not abandon the other 1000+ pinned projects on the first transient
        # fetch failure. Complete one bounded pass so its failed-project list
        # can be inspected and resumed; never silently refreeze upstream HEAD.
        run([launcher, "sync", "-c", "--no-tags", "-j", args.jobs, "--no-clone-bundle"], checkout, env)
    actual = run([launcher, "manifest", "-r"], checkout, env, True)
    expected_projects = {item.get("path", item.get("name")): item.get("revision") for item in ET.fromstring(raw).findall("project")}
    actual_projects = {item.get("path", item.get("name")): item.get("revision") for item in ET.fromstring(actual).findall("project")}
    if actual_projects != expected_projects:
        raise ValueError("Independent checkout differs from the pinned project commits.")
    if args.repair_missing_indexes:
        if metadata["status"] != "preparing-source-not-built":
            raise ValueError("Index recovery is restricted to unfinished source preparation.")
        repair_missing_indexes(checkout, raw, env)
    dirty = run([launcher, "forall", "-c", "git status --porcelain --untracked-files=normal"], checkout, env, True)
    if dirty.strip():
        raise ValueError("Fresh upstream checkout has uncommitted files; refusing release preparation.")
    metadata["status"] = "clean-pinned-upstream-ready-not-built"
    (record / "prepare.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print("CLEAN_PINNED_SOURCE_READY", json.dumps(metadata), flush=True)


if __name__ == "__main__":
    main()
