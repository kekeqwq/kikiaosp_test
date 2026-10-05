#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Collect actual kernel and notice-identified copyleft sources; never disks.

Requires the exact clean release package and build/package audit records.
Exports AOSP projects at manifest commits, not integrated working-tree files;
the exact device tree supplies the reviewed integration patches separately.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile
import xml.etree.ElementTree as ET
import zipfile


PROJECTS = {
    'AndroidNeuralNetworks': 'packages/modules/NeuralNetworks',
    'ANGLE_v_1.0': 'external/angle', 'bpftool': 'external/bpftool',
    'dnsmasq_v_2.51': 'external/dnsmasq', 'e2fsprogs_v1.47.2': 'external/e2fsprogs',
    'exfatprogs': 'external/exfatprogs', 'f2fs-tools': 'external/f2fs-tools',
    'fec_v_3.0.1': 'external/fec',
    'freetype_v_02001430cad080e8103a891c229e8cf24f4ef447': 'external/freetype',
    'gptfdisk_v_cb4bf320748f701a0ed835d4a410f2960f1ce0bd': 'external/gptfdisk',
    'ICU_v_78': 'external/icu', 'iproute2_v4.14.1': 'external/iproute2',
    'iptables_v1.8.11': 'external/iptables', 'libcap_v_libcap-2.69': 'external/libcap',
    'libexif_v_0.6.21': 'external/libexif', 'libnl': 'external/libnl',
    'system/bpfprogs': 'system/bpfprogs',
}
# Build definitions, platform interfaces and shared dependencies used by the
# above projects. The complete pinned manifest permits the full AOSP build.
BUILD_PROJECTS = ['build/make', 'build/soong', 'bionic', 'system/core',
                  'system/libbase', 'system/logging', 'system/vold',
                  'external/zlib', 'external/libcxx', 'external/compiler-rt',
                  'external/boringssl', 'external/selinux', 'external/libpng',
                  'external/libjpeg-turbo', 'external/expat', 'external/protobuf',
                  'external/fmtlib']


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def git_export(repo, revision, destination):
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('Only full source commit IDs are supported')
    subprocess.run(['git', '-C', str(repo), 'cat-file', '-e', revision + '^{commit}'], check=True)
    subprocess.run(['git', '-C', str(repo), 'archive', '--format=tar',
                    '-o', str(destination), revision], check=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['package', 'build-audit', 'package-audit', 'device-repo', 'kernel-repo', 'output']:
        p.add_argument('--' + name, required=True, type=Path)
    args = p.parse_args()
    build = json.loads(args.build_audit.read_text())
    audit = json.loads(args.package_audit.read_text())
    with zipfile.ZipFile(args.package) as z:
        lock = json.loads(z.read('provenance/source-lock.json'))
        notices = z.read('licenses/aosp.txt').decode('utf-8')
    if (sha(args.package) != audit['package']['sha256'] or
            lock['device']['commit'] != build['deviceCommit'] or
            lock['kernel']['commit'] != build['kernelCommit'] or
            lock['aosp']['manifestSha256'] != build['manifestSha256']):
        raise ValueError('Package/source audit mismatch')
    ids = {m[0] for m in re.findall(r'<file-content\s+contentId="([^"]+)"[^>]*>(.*?)</file-content>', notices, re.S)
           if re.search(r'GNU (?:LESSER |LIBRARY )?GENERAL PUBLIC LICENSE', m[1])}
    labels = {m[1] for m in re.findall(r'<file-name\s+contentId="([^"]+)"\s+lib="([^"]+)"[^>]*>', notices)
              if m[0] in ids}
    if labels - PROJECTS.keys():
        raise ValueError('Unmapped copyleft notice components: ' + repr(sorted(labels - PROJECTS.keys())))
    manifest = lock['aosp']['manifestXml']
    projects = {e.get('path', e.get('name')): e for e in ET.fromstring(manifest).findall('project')}
    selected = sorted({PROJECTS[label] for label in labels} | set(BUILD_PROJECTS))
    if set(selected) - projects.keys():
        raise ValueError('Required source project missing from pinned manifest: ' + repr(set(selected) - projects.keys()))
    output = args.output.absolute()
    output.mkdir(exist_ok=False, parents=False)
    aosp_dir = output / 'aosp-projects'
    aosp_dir.mkdir()
    source_records = []
    for path in selected:
        project = projects[path]
        destination = aosp_dir / (path.replace('/', '--') + '.tar')
        print('Exporting pinned AOSP source:', path, flush=True)
        git_export(Path(build['aosp']) / path, project.get('revision'), destination)
        source_records.append({'path': path, 'name': project.get('name'), 'commit': project.get('revision'),
                               'archive': 'aosp-projects/' + destination.name, 'sha256': sha(destination)})
    for name, repo, revision in [('device', args.device_repo, build['deviceCommit']),
                                  ('kernel-recipe', args.kernel_repo, build['kernelCommit'])]:
        git_export(repo, revision, output / (name + '.tar'))
    git_export(args.device_repo, audit['packagingCommit'], output / 'package-recipe.tar')
    kernel_source = Path(audit['kernelGraph']['source'])
    if not kernel_source.is_dir() or not str(kernel_source).startswith('/nix/store/'):
        raise ValueError('Expected the actual recorded immutable Nix kernel source')
    print('Archiving the exact Linux source consumed by Nix (recipe patches are in kernel-recipe.tar).', flush=True)
    source_version = lock['kernel']['sourceVersion']
    if not re.fullmatch(r'7\.3-rc[56]', source_version):
        raise ValueError('Unexpected pinned kernel source version')
    source_archive = output / ('linux-' + source_version + '-source.tar.gz')
    subprocess.run(['tar', '-czf', str(source_archive), '-C', str(kernel_source), '.'], check=True)
    # Extract ACTUAL final config embedded in the kernel being shipped, not
    # the declarative input or a possibly GC-rebuilt mutable Nix output path.
    image = args.build_audit.parent / 'kernel-result/boot/kernel'
    if sha(image) != lock['kernel']['imageSha256']:
        raise ValueError('Actual shipped kernel image changed')
    actual_config = subprocess.check_output(['bash', str(kernel_source / 'scripts/extract-ikconfig'), str(image)])
    if b'CONFIG_ARM64_4K_PAGES=y' not in actual_config or b'CONFIG_SND_VIRTIO=y' not in actual_config:
        raise ValueError('Could not extract the actual required built kernel configuration')
    (output / 'linux-built.config').write_bytes(actual_config)
    (output / 'linux-declared.config').write_bytes((args.build_audit.parent / 'kernel-result/boot/config').read_bytes())
    (output / 'aosp-pinned-manifest.xml').write_text(manifest, encoding='utf-8')
    (output / 'source-lock.json').write_text(json.dumps(lock, indent=2) + '\n')
    (output / 'aosp-notices.txt').write_text(notices, encoding='utf-8')
    provenance = {'version': '0.3.0-alpha', 'packageSha256': sha(args.package),
                  'builtDeviceCommit': build['deviceCommit'], 'kernelCommit': build['kernelCommit'],
                  'noticeIdentifiedCopyleftComponents': sorted(labels), 'projects': source_records,
                  'kernelSourceArchive': source_archive.name, 'kernelSourceArchiveSha256': sha(source_archive),
                  'kernelBuiltConfigSha256': hashlib.sha256(actual_config).hexdigest(),
                  'kernelInputGraph': audit['kernelGraph']}
    (output / 'source-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    (output / 'BUILDING.txt').write_text(
        'KikiAOSP 0.3 Alpha corresponding-source materials\n\n'
        'Unpack device.tar and kernel-recipe.tar into separate Git-capable source trees.\n'
        'The Linux archive is the exact immutable Nix source before applying the two tracked recipe patches.\n'
        'kernel-recipe.tar contains flake.nix, flake.lock, configuration and patches; use nix build.\n'
        'The device README.md and RELEASE_POLICY.md describe complete AOSP preparation/build/packaging.\n'
        'Restore the exact aosp-pinned-manifest.xml with repo, sync its fixed commits, apply the device\n'
        'integration scripts, and select kikiaosp_test_arm64_phone_release-cp2a-userdebug.\n'
        'The original preferred sources for every notice-identified GPL/LGPL project and the listed\n'
        'platform build interfaces are supplied as separate tar files. These are Git archives of\n'
        'manifest revisions; apply the exact integration patches in device.tar, not a working-tree copy.\n'
        'Remaining AOSP sources/toolchains are identified by the complete pinned HTTPS manifest.\n'
        'Keep all original per-file licenses/notices. LGPL shared libraries may be rebuilt/replaced\n'
        'by building a new system package; no locked bootloader or modified-library prohibition is used.\n'
        'This source kit contains no userdata/disk, credentials, developer logs or build output images.\n'
        'This is a NONRELEASE native OTA candidate; no public tag or Release is claimed.\n'
        'Actual built device identity above, not a later pipeline HEAD, describes the system.\n'
        'linux-built.config was extracted from the exact shipped kernel; linux-declared.config is the recipe input.\n'
        'Any historical retained-kernel / Nix rebuild byte difference is recorded explicitly in source-provenance.json.\n')
    destination = output.with_name('KikiAOSP-0.3.0-alpha-source-kit.tar.gz')
    if destination.exists():
        raise ValueError('Never replace an existing source kit')
    with tarfile.open(destination, 'w:gz', compresslevel=4) as tar:
        tar.add(output, arcname='source-kit')
    print(json.dumps({'archive': str(destination), 'bytes': destination.stat().st_size, 'sha256': sha(destination)}), flush=True)


if __name__ == '__main__':
    main()
