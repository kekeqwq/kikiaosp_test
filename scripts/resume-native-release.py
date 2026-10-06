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
 if audit['phase'] not in ('building-aosp','clean-candidate-inputs-built-not-packaged-or-accepted') or audit['recipe']!='kikiaosp-release-v1' or audit['systemVersion'] not in ('0.3.0-alpha','0.3.1-alpha') or a.new_stage.exists():raise ValueError('Only this exact audited native release compiler can resume to a NEW record')
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
 changed=subprocess.check_output(['git','-C',str(a.pipeline),'diff','--name-only',audit['deviceCommit'],dc,'--',rel,'patches','overlays']).decode().splitlines()
 allowed=[['device/kiki/kikiaosp_test/ota/src/com/kiki/updater/UpdateService.java'],['device/kiki/kikiaosp_test/BoardConfig.mk','device/kiki/kikiaosp_test/ota/product.mk'],['device/kiki/kikiaosp_test/ota/compatibility_matrix.kiki.xml','device/kiki/kikiaosp_test/ota/manifest.kiki_kernel.xml','device/kiki/kikiaosp_test/ota/product.mk'],['device/kiki/kikiaosp_test/ota/manifest.kiki_kernel.xml'],['device/kiki/kikiaosp_test/ota/AndroidManifest.xml','device/kiki/kikiaosp_test/ota/src/com/kiki/updater/UpdateActivity.java','device/kiki/kikiaosp_test/ota/src/com/kiki/updater/UpdateService.java'],['device/kiki/kikiaosp_test/ota/product.mk'],['device/kiki/kikiaosp_test/ota/AndroidManifest.xml','device/kiki/kikiaosp_test/ota/res/values/styles.xml','device/kiki/kikiaosp_test/ota/src/com/kiki/updater/UpdateActivity.java','device/kiki/kikiaosp_test/ota/src/com/kiki/updater/UpdateService.java']]
 branch=subprocess.check_output(['git','-C',str(a.pipeline),'branch','--show-current']).decode().strip()
 storage_paths=sorted([rel+'/ota/Android.bp',rel+'/ota/product.mk',rel+'/kikiaosp_test_arm64_phone_release.mk',rel+'/ota/storage/StorageImageSizes.h',rel+'/ota/storage/kiki_storage_stats.cpp',rel+'/ota/storage/kiki-storage-accounting.rc',rel+'/ota/src/com/kiki/updater/UpdateService.java','patches/aosp-kikiaosp-sparse-ab-storage-accounting.patch','overlays/frameworks/base/packages/SettingsLib/src/com/android/settingslib/deviceinfo/KikiStorageAccounting.java'])
 storage_fix=branch=='fix/alpha-0.3.1-storage-accounting' and sorted(changed)==storage_paths and audit['deviceCommit']=='4b3e71fca9d63c1f8ce3be5430444c7c52290971'
 storage_retry=branch=='fix/alpha-0.3.1-storage-accounting' and changed==[rel+'/ota/Android.bp'] and audit['deviceCommit']=='fd04174394d8bd70fde156f62271eb5ddbfb965d'
 if storage_retry:
  old_bp=(snap/rel/'ota/Android.bp').read_text();new_bp=(a.pipeline/rel/'ota/Android.bp').read_text()
  if new_bp != old_bp.replace('    cpp_std: "c++17",\n','    cpp_std: "c++17",\n    cppflags: ["-fexceptions"],\n'):raise ValueError('Only the actual leaf-module exception-flag repair is allowed')
 if storage_fix:
  old_product=(snap/rel/'ota/product.mk').read_text();new_product=(a.pipeline/rel/'ota/product.mk').read_text()
  if new_product != old_product.replace('ro.kiki.ota.sequence=4','ro.kiki.ota.sequence=5')+'\nPRODUCT_PACKAGES += kiki_storage_stats\n':raise ValueError('Unexpected publisher sequence/native-package change')
 elif not storage_retry and changed not in allowed:raise ValueError('In-place retry only permits reviewed, explicitly bounded fixes')
 if changed==['device/kiki/kikiaosp_test/ota/product.mk']:
  branch=subprocess.check_output(['git','-C',str(a.pipeline),'branch','--show-current']).decode().strip()
  old_product=(snap/changed[0]).read_bytes();new_product=(a.pipeline/changed[0]).read_bytes()
  source_value,target_value=(b'ro.kiki.ota.sequence=1',b'ro.kiki.ota.sequence=2') if branch=='test/native-ota-sequence2-nonrelease' else (b'ro.kiki.ota.sequence=2',b'ro.kiki.ota.sequence=3') if branch=='test/native-ota-sequence3-nonrelease' else (b'ro.kiki.ota.sequence=3',b'ro.kiki.ota.sequence=4') if branch=='test/native-ota-sequence4-nonrelease' else (b'',b'')
  if not source_value or old_product.count(source_value)!=1 or new_product!=old_product.replace(source_value,target_value):raise ValueError('Only explicitly bounded NONRELEASE sequence1-to2, sequence2-to3 or sequence3-to4 test system property changes are permitted')
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
 if storage_fix:
  run('git','-C',aosp,'apply','--check',record/'device-source/patches/aosp-kikiaosp-sparse-ab-storage-accounting.patch')
  run('git','-C',aosp,'apply',record/'device-source/patches/aosp-kikiaosp-sparse-ab-storage-accounting.patch')
  overlay=record/'device-source/overlays/frameworks/base/packages/SettingsLib/src/com/android/settingslib/deviceinfo/KikiStorageAccounting.java'
  destination=aosp/'frameworks/base/packages/SettingsLib/src/com/android/settingslib/deviceinfo/KikiStorageAccounting.java'
  if destination.exists():raise ValueError('Unexpected pre-existing new accounting overlay')
  shutil.copy2(overlay,destination)
 run('bash',record/'device-source/scripts/audit-aosp-integration.sh',aosp)
 mode='Audited failed native release-only compiler output resumed IN PLACE; same physical paths, reviewed whitelist-only fixes; unchanged device file timestamps preserved after byte checks; no development/userdata; incremental rebuild'
 source['sharedInputs']=mode;source['nativeRetryBaseRecord']=str(old);(prep/'prepare.json').write_text(json.dumps(source,indent=2)+'\n')
 audit.update(deviceCommit=dc,systemVersion='0.3.1-alpha' if storage_fix else audit['systemVersion'],phase='building-aosp',sharedInputs=mode,nativeRetryBaseRecord=str(old),nativeRetryBaseDeviceCommit=actual,nativeRetryChangedDevicePaths=changed)
 for k in ('images','verifiedProperties'):audit.pop(k,None)
 (record/'build-audit.json').write_text(json.dumps(audit,indent=2)+'\n')
 (a.new_stage/'retry-provenance.json').write_text(json.dumps({'oldRecord':str(old),'newRecord':str(record),'oldDeviceCommit':actual,'newDeviceCommit':dc,'aosp':str(aosp),'output':str(out),'changedDevicePaths':changed,'notEmptyOutput':True,'notYetBuilt':True},indent=2)+'\n')
 print('Audited native compiler retry ready; not a successful build/OTA acceptance.',flush=True)

if __name__=='__main__':main()
