#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Finish a reviewed failed native PACKAGE before any payload existed.

Keeps the already-pinned baseline/target-files, authenticates every boot/system/
vendor byte against both the audited intermediate and adapted target-files.
Not a system build, old instance or resume of a payload application.
"""
import argparse,hashlib,importlib.util,json,os,subprocess,zipfile,shutil
from pathlib import Path

def load(p,name):
 s=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m

def main():
 p=argparse.ArgumentParser();p.add_argument('--pipeline',type=Path,required=True);p.add_argument('--package',type=Path,required=True);p.add_argument('--intermediate',type=Path,required=True);p.add_argument('--preparation',type=Path,required=True);p.add_argument('--record',type=Path,required=True);p.add_argument('--host',type=Path,required=True);p.add_argument('--key-base',type=Path,required=True);p.add_argument('--sequence',type=int,required=True);p.add_argument('--version',required=True);a=p.parse_args()
 for n in ('pipeline','package','intermediate','preparation','record','host'):setattr(a,n,getattr(a,n).resolve(strict=True))
 a.key_base=a.key_base.resolve();m=load(a.pipeline/'scripts/package-native-ab.py','native');aud=load(a.pipeline/'scripts/package-clean-release.py','audit');aud.audit_inputs(a.preparation,a.record)
 stage=a.package/'material';target=a.package/'native-target-files.zip';baseline=a.package/'KikiAOSP-0.3.0-alpha-arm64-ab.zip';native=a.package/'android-native-full.ota.zip'
 if native.exists() or any((a.package/n).exists() for n in ('KikiAOSP-ota.json','KikiAOSP-ota.sig','KikiAOSP-0.3.0-alpha-full.ota.zip','native-ota-proof.json')):raise ValueError('Only a failed PACKAGE that never generated a payload can finish')
 with zipfile.ZipFile(baseline) as z,zipfile.ZipFile(a.intermediate) as i,zipfile.ZipFile(target) as t:
  manifest=json.loads(z.read('manifest.json'));lock=json.loads(z.read(manifest['sourceLock']['path']));parts=t.read('META/ab_partitions.txt').decode().split()
  if manifest['formatVersion']!=2 or manifest['layoutVersion']!='gpt-ab-v1' or set(parts)!=set(m.CAP) or len(parts)!=3:raise ValueError('Not the bounded native package')
  for item in manifest['payloads']:
   role=item['role'];actual=m.digest(stage/(role+'.img'))
   if actual!=item['sha256'] or (stage/(role+'.img')).stat().st_size!=item['bytes'] or item['partitionBytes']!=m.CAP[role]:raise ValueError('Material image changed')
   for archive,path in ((z,item['path']),(i,item['path']),(t,'IMAGES/'+role+'.img')):
    h=hashlib.sha256()
    with archive.open(path) as f:
     for b in iter(lambda:f.read(1<<20),b''):h.update(b)
    if h.hexdigest()!=actual:raise ValueError('Audited intermediate/baseline/target-files diverged')
  if hashlib.sha256(z.read(manifest['sourceLock']['path'])).hexdigest()!=manifest['sourceLock']['sha256']:raise ValueError('Frozen baseline source lock changed')
 # Freshly reconstruct adapter from the clean pinned source and matching built
 # binary, rather than executing an inherited failed-package replacement.
 adapted=a.package/'physical-ab-ota-tool-finish.pyz';adapter=m.physical_ab_tool(a.host,a.record,adapted)
 env=dict(os.environ,PATH=str(a.host/'bin')+':/usr/bin:/bin',LD_LIBRARY_PATH=str(a.host/'lib64'))
 m.run([adapted,'-p',a.host,'--no_signing','--skip_postinstall','--max_threads=8','-k',a.key_base,target,native],env)
 with zipfile.ZipFile(native) as n:
  m.unpack(n,'payload.bin',stage/'payload.bin');properties=n.read('payload_properties.txt');metadata=n.read('META-INF/com/android/metadata')
 with (stage/'payload.bin').open('rb') as f:
  if f.read(4)!=b'CrAU':raise ValueError('Not an Android payload')
 cat={'kind':'org.kiki.ota.full','format':1,'device':'kikiaosp_test','layout':'gpt-ab-v1','android_major':17,'sequence':a.sequence,'version':a.version,'payload_sha256':m.digest(stage/'payload.bin'),'payload_bytes':(stage/'payload.bin').stat().st_size,'ota_url':''}
 (a.package/'KikiAOSP-ota.json').write_bytes(m.raw(cat));signature=a.package/'KikiAOSP-ota.sig';m.run(['openssl','dgst','-sha256','-sign',a.key_base.with_suffix('.pem'),'-out',signature,a.package/'KikiAOSP-ota.json'])
 if signature.stat().st_size!=256:raise ValueError('Unexpected publisher RSA signature size')
 wrapper=a.package/'KikiAOSP-0.3.0-alpha-full.ota.zip'
 with zipfile.ZipFile(wrapper,'x',compression=zipfile.ZIP_STORED) as z:
  z.write(stage/'payload.bin','payload.bin');z.writestr('payload_properties.txt',properties);z.writestr('META-INF/com/android/metadata',metadata);z.writestr('kiki-ota.json',m.raw(cat));z.write(signature,'kiki-ota.sig')
 proof={'kind':'org.kiki.native-ota-build-proof','nonrelease':True,'sequence':a.sequence,'packageResumeNotSystemRebuild':True,'sourceIntermediateSha256':m.digest(a.intermediate),'adaptedTargetFilesSha256':m.digest(target),'baselineSha256':m.digest(baseline),'otaSha256':m.digest(wrapper),'payloadSha256':cat['payload_sha256'],'deviceBuiltCommit':lock['device']['commit'],'contractPipelineCommit':lock['contract']['revision'],'finishPipelineCommit':subprocess.check_output(['git','-C',str(a.pipeline),'rev-parse','HEAD']).decode().strip(),'partitionRoles':list(m.CAP),'userdataTouched':False,'physicalAbHostToolAdaptation':adapter}
 (a.package/'native-ota-proof.json').write_bytes(m.raw(proof));print(json.dumps(proof,indent=2),flush=True)

if __name__=='__main__':main()
