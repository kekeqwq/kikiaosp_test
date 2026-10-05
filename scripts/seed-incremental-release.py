#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Seed a versioned incremental candidate from audited RELEASE inputs only.

Requires completed Btrfs reflink copies into NEW source/output paths. Never
imports development images or userdata. The original release trees stay
unchanged. This is not a clean-from-empty-output build and records that fact.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess


def run(*args):
    subprocess.run(list(map(str, args)), check=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--old-preparation', type=Path, required=True)
    p.add_argument('--old-record', type=Path, required=True)
    p.add_argument('--old-pipeline', type=Path, required=True)
    p.add_argument('--aosp', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--preparation', type=Path, required=True)
    p.add_argument('--record', type=Path, required=True)
    p.add_argument('--kernel', type=Path, required=True)
    a = p.parse_args()
    device = Path(__file__).resolve().parent.parent
    old = a.old_record.resolve(strict=True)
    spec = importlib.util.spec_from_file_location('old_packager', a.old_pipeline.resolve(strict=True) / 'scripts/package-clean-release.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.builder.clean(a.old_pipeline)
    source, audit, raw, _, _, _ = mod.audit_inputs(a.old_preparation.resolve(strict=True), old)
    aosp, out = a.aosp.resolve(strict=True), a.output.resolve(strict=True)
    if aosp == Path(audit['aosp']) or out == Path(audit['output']):
        raise ValueError('Never modify original release source/output.')
    if a.preparation.exists() or a.record.exists():
        raise ValueError('New preparation and record required.')
    mod.builder.clean(device)
    mod.builder.clean(a.kernel)
    actual = subprocess.check_output([aosp / '.repo/repo/repo', 'manifest', '-r'], cwd=aosp)
    if mod.builder.commits(actual) != mod.builder.commits(raw):
        raise ValueError('Cloned upstream manifest differs.')
    # Validate cloned image bytes BEFORE any new build, not a guessed cache.
    for name, expected in audit['images'].items():
        mod.verify_record(out / 'target/product/kikiaosp_test' / name, expected)
    alias = aosp / 'out'
    if not alias.is_symlink() or alias.resolve() != Path(audit['output']):
        raise ValueError('Unexpected cloned output alias.')
    alias.unlink()
    alias.symlink_to(out, target_is_directory=True)
    a.preparation.mkdir(parents=True)
    shutil.copytree(a.old_preparation / 'manifest-repo', a.preparation / 'manifest-repo')
    mode = f"Audited {audit['systemVersion']} release source/output Btrfs reflink clone; incremental rebuild, no development inputs"
    source.update(checkout=str(aosp), sharedInputs=mode, incrementalBaseDeviceCommit=audit['deviceCommit'])
    (a.preparation / 'prepare.json').write_text(json.dumps(source, indent=2) + '\n')
    a.record.mkdir(parents=True)
    dc = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=device).decode().strip()
    kc = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=a.kernel).decode().strip()
    run('git', '-C', device, 'worktree', 'add', '--detach', a.record / 'device-source', dc)
    run('git', '-C', a.kernel, 'worktree', 'add', '--detach', a.record / 'kernel-source', kc)
    kernel_result = (a.kernel / 'build/result').resolve(strict=True)
    (a.record / 'kernel-result').symlink_to(kernel_result, target_is_directory=True)
    snapshot = a.record / 'device-source'
    run('bash', snapshot / 'scripts/sync-device-tree.sh', aosp)
    # An audited prior 0.3 candidate may already include the audio delta.
    # Undo ONLY its exact frozen patch before applying the current snapshot;
    # do not assume a legacy tinyalsa implementation or force/stack patches.
    inherited_audio = old / 'device-source/patches/aosp-kikiaosp-synchronous-pcm.patch'
    if inherited_audio.exists():
        run('git', '-C', aosp, 'apply', '--reverse', '--check', inherited_audio)
        run('git', '-C', aosp, 'apply', '--reverse', inherited_audio)
    audio_patch = snapshot / 'patches/aosp-kikiaosp-synchronous-pcm.patch'
    run('git', '-C', aosp, 'apply', '--check', audio_patch)
    run('git', '-C', aosp, 'apply', audio_patch)
    inherited_wipe = old / 'device-source/patches/aosp-kikiaosp-ota-no-userdata-wipe.patch'
    if inherited_wipe.exists():
        run('git', '-C', aosp, 'apply', '--reverse', '--check', inherited_wipe)
        run('git', '-C', aosp, 'apply', '--reverse', inherited_wipe)
    no_wipe = snapshot / 'patches/aosp-kikiaosp-ota-no-userdata-wipe.patch'
    run('git', '-C', aosp, 'apply', '--check', no_wipe)
    run('git', '-C', aosp, 'apply', no_wipe)
    run('bash', snapshot / 'scripts/audit-aosp-integration.sh', aosp)
    value = dict(audit, deviceCommit=dc, kernelCommit=kc, aosp=str(aosp), output=str(out),
                 systemVersion='0.3.0-alpha', phase='building-aosp', sharedInputs=mode,
                 incrementalBaseRecord=str(old), incrementalBaseImageHashes=audit['images'],
                 kernelImageSha256=mod.builder.digest(kernel_result / 'boot/kernel'),
                 flakeLockSha256=mod.builder.digest(a.kernel / 'flake.lock'))
    value.pop('images', None)
    value.pop('verifiedProperties', None)
    (a.record / 'build-audit.json').write_text(json.dumps(value, indent=2) + '\n')
    print('Audited incremental release seed ready; not built or accepted.', flush=True)


if __name__ == '__main__':
    main()
