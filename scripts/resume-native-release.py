#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Audited IN-PLACE retry of this failed release-only compiler run.

Keeps the physical source/output paths stable, so an APK fix does not force a
rebuild of unrelated Android modules. NEW frozen record, not an empty build or
a claim that the prior failed record now describes the changed working tree.
"""
import argparse,hashlib,importlib.util,json,os,shutil,subprocess
from pathlib import Path

def run(*args):print('RUN:',*map(str,args),flush=True);subprocess.run(list(map(str,args)),check=True)
def module(path):
 s=importlib.util.spec_from_file_location('packer',path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m

def main():
 p=argparse.ArgumentParser();p.add_argument('--pipeline',type=Path,required=True);p.add_argument('--old-stage',type=Path,required=True);p.add_argument('--new-stage',type=Path,required=True);a=p.parse_args()
 old=a.old_stage/'build-record';old_pre=a.old_stage/'preparation';audit=json.loads((old/'build-audit.json').read_text());source=json.loads((old_pre/'prepare.json').read_text())
 if audit['phase'] not in ('building-aosp','clean-candidate-inputs-built-not-packaged-or-accepted') or audit['recipe']!='kikiaosp-release-v1' or audit['systemVersion']!='0.3.0-alpha' or a.new_stage.exists():raise ValueError('Only this exact failed native release compiler can resume to a NEW record')
 aosp=Path(audit['aosp']).resolve();out=Path(audit['output']).resolve();snap=old/'device-source'
 if not str(aosp).startswith('/home/keke/aosp-release-0.3-ota-') or not str(out).startswith('/home/keke/aosp-release-output-0.3-ota-'):raise ValueError('Not an owned native release-only source/output')
 if (aosp/'out').resolve()!=out:raise ValueError('Physical source/output alias changed')
 dc=subprocess.check_output(['git','-C',str(a.pipeline),'rev-parse','HEAD']).decode().strip()
 actual=subprocess.check_output(['git','-C',str(snap),'rev-parse','HEAD']).decode().strip()
 if actual!=audit['deviceCommit']:raise ValueError('Old frozen source commit changed')
 run('bash',snap/'scripts/audit-aosp-integration.sh',aosp)
 # ENTIRE old device overlay must still equal its frozen source. No experiment,
 # native secret/generated signing files or development userdata can be inherited.
 rel='device/kiki/kikiaosp_test';names=subprocess.check_output(['git','-C',str(snap),'ls-files','-z','--',rel]).decode().split('\0');names=set(filter(None,names))
 actual_names={f.relative_to(aosp).as_posix() for f in (aosp/rel).rglob('*') if f.is_file() or f.is_symlink()}
 if actual_names!=names:raise ValueError('Old device overlay includes unexpected files')
 for n in names:
  if (aosp/n).read_bytes()!=(snap/n).read_bytes():raise ValueError('Old integrated source changed: '+n)
 check=module(a.pipeline/'scripts/prepare-native-build-inputs.py');check.verify(aosp,old)
 changed=subprocess.check_output(['git','-C',str(a.pipeline),'diff','--name-only',audit['deviceCommit'],dc,'--',rel,'patches']).decode().splitlines()
 allowed=[['device/kiki/kikiaosp_test/ota/src/com/kiki/updater/UpdateService.java'],['device/kiki/kikiaosp_test/BoardConfig.mk','device/kiki/kikiaosp_test/ota/product.mk'],['device/kiki/kikiaosp_test/ota/compatibility_matrix.kiki.xml','device/kiki/kikiaosp_test/ota/manifest.kiki_kernel.xml','device/kiki/kikiaosp_test/ota/product.mk']]
 if changed not in allowed:raise ValueError('In-place retry only permits reviewed updater, direct-boot or explicit audited non-GKI VINTF configuration fixes')
 a.new_stage.mkdir();prep=a.new_stage/'preparation';shutil.copytree(old_pre,prep);record=a.new_stage/'build-record';record.mkdir()
 kernel_repo=subprocess.check_output(['git','-C',str(old/'kernel-source'),'rev-parse','--git-common-dir']).decode().strip()
 kernel_source=old/'kernel-source';run('git','-C',a.pipeline,'worktree','add','--detach',record/'device-source',dc);run('git','-C',kernel_source,'worktree','add','--detach',record/'kernel-source',audit['kernelCommit'])
 (record/'kernel-result').symlink_to((old/'kernel-result').resolve(),target_is_directory=True)
 times={n:(aosp/n).stat() for n in names if n not in changed}
 run('bash',record/'device-source/scripts/sync-device-tree.sh',aosp)
 # Frozen worktrees get fresh mtimes. Preserve OLD timestamps only for files
 # proven byte-identical before and after sync, not for reviewed changed files.
 for n,st in times.items():
  if (aosp/n).read_bytes()!=(snap/n).read_bytes():raise ValueError('Unexpected retry mutation: '+n)
  os.utime(aosp/n,ns=(st.st_atime_ns,st.st_mtime_ns))
 run('bash',record/'device-source/scripts/audit-aosp-integration.sh',aosp)
 mode='Audited failed native release-only compiler output resumed IN PLACE; same physical paths, reviewed whitelist-only fixes; unchanged device file timestamps preserved after byte checks; no development/userdata; incremental rebuild'
 source['sharedInputs']=mode;source['nativeRetryBaseRecord']=str(old);(prep/'prepare.json').write_text(json.dumps(source,indent=2)+'\n')
 audit.update(deviceCommit=dc,phase='building-aosp',sharedInputs=mode,nativeRetryBaseRecord=str(old),nativeRetryBaseDeviceCommit=actual,nativeRetryChangedDevicePaths=changed)
 for k in ('images','verifiedProperties'):audit.pop(k,None)
 (record/'build-audit.json').write_text(json.dumps(audit,indent=2)+'\n')
 (a.new_stage/'retry-provenance.json').write_text(json.dumps({'oldRecord':str(old),'newRecord':str(record),'oldDeviceCommit':actual,'newDeviceCommit':dc,'aosp':str(aosp),'output':str(out),'changedDevicePaths':changed,'notEmptyOutput':True,'notYetBuilt':True},indent=2)+'\n')
 print('Audited native compiler retry ready; not a successful build/OTA acceptance.',flush=True)

if __name__=='__main__':main()
