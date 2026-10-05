#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Expose the SAME audited Nix kernel to Android's standard kernel/target-files target.

No secret keys, downloaded tools or extra untracked device sources. These are
explicit generated build inputs, outside the integrated device source snapshot.
"""
import argparse,hashlib,json,shutil
from pathlib import Path

def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1<<20),b''):h.update(b)
 return h.hexdigest()

def verify(aosp,record):
 audit=json.loads((record/'build-audit.json').read_text())
 root=aosp/'.kiki-native-inputs'
 if root.is_symlink() or (root/'kernel').is_symlink():raise ValueError('Redirected native generated inputs')
 data=json.loads((root/'inputs.json').read_text())
 if data!={'kind':'org.kiki.native-build-inputs','kernelSha256':audit['kernelImageSha256']} or digest(root/'kernel')!=audit['kernelImageSha256']:raise ValueError('Native kernel does not match actual audited Nix build')

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--aosp',type=Path,required=True);p.add_argument('--record',type=Path,required=True);a=p.parse_args()
 audit=json.loads((a.record/'build-audit.json').read_text());kernel=a.record/'kernel-result/boot/kernel'
 if digest(kernel)!=audit['kernelImageSha256']:raise ValueError('Audited kernel changed')
 dest=a.aosp/'.kiki-native-inputs';dest.mkdir(exist_ok=False)
 shutil.copyfile(kernel,dest/'kernel')
 (dest/'inputs.json').write_text(json.dumps({'kind':'org.kiki.native-build-inputs','kernelSha256':audit['kernelImageSha256']},indent=2)+'\n')
 verify(a.aosp,a.record)
