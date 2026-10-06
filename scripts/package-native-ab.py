#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""NEW format-2 baseline and publisher-signed FULL native Android A/B payload.

The intermediate is an audited build artifact, never an old instance/data disk.
Uses the same build's target-files and host OTA tools. Does not publish anything.
"""
import argparse,hashlib,importlib.util,json,os,shutil,stat,subprocess,zipfile
from pathlib import Path
import jsonschema

CAP={'boot':64<<20,'system':4<<30,'vendor':512<<20}
FEATURES=['boot-v4-direct','gpt-ab-v1','fresh-f2fs','exact-total-storage','sdl-native-pixels','virgl','guest-120hz','instance-isolation-v1','surface-camera-v1','native-full-ota-v1']

def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for b in iter(lambda:f.read(1<<20),b''):h.update(b)
 return h.hexdigest()
def raw(j):return (json.dumps(j,ensure_ascii=True,sort_keys=True,separators=(',',':'))+'\n').encode()
def run(args,env=None):print('RUN:',*map(str,args),flush=True);subprocess.run(list(map(str,args)),check=True,env=env)
def unpack(z,name,out):
 if out.exists():raise ValueError('Never replace extracted input')
 with z.open(name) as i,out.open('xb') as o:shutil.copyfileobj(i,o,1<<20)
def copy_entry(src,dst,info):
 with src.open(info.filename) as i,dst.open(info,'w',force_zip64=info.file_size>=2<<30) as o:shutil.copyfileobj(i,o,1<<20)

def filesystem_tree(root):
 out={}
 for p in root.rglob('*'):
  s=p.lstat();mode=stat.S_IMODE(s.st_mode)
  if p.is_symlink():value='link:'+os.readlink(p)
  elif p.is_dir():value='dir'
  elif stat.S_ISREG(s.st_mode):value='sha256:'+digest(p)
  else:raise ValueError('Unexpected reconstructed filesystem special file')
  out[p.relative_to(root).as_posix()]=(mode,value)
 return out

def physical_ab_tool(host,record,dest):
 # Android17 release tool unconditionally edits nonexistent dynamic metadata
 # when ublk is unsupported, including physical A/B. Bound a HOST-ONLY fix
 # to the pinned clean build/make source; keep the compiled tool dependencies.
 source=Path(json.loads((record/'build-audit.json').read_text())['aosp'])/'build/make'
 path='tools/releasetools/ota_from_target_files.py'
 commit=subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD']).decode().strip()
 content=subprocess.check_output(['git','-C',str(source),'show','HEAD:'+path])
 if content!=(source/path).read_bytes():raise ValueError('OTA tool source not pinned clean upstream')
 old=b'  if OPTIONS.disable_ublk:\n    logger.info("Disabling UBLK as requested")'
 new=b'  if OPTIONS.disable_ublk and OPTIONS.info_dict.get("use_dynamic_partitions") == "true":\n    logger.info("Disabling UBLK as requested")'
 if content.count(old)!=1:raise ValueError('Physical A/B host-tool repair no longer matches reviewed upstream')
 patched=content.replace(old,new)
 tool=host/'bin/ota_from_target_files'
 with zipfile.ZipFile(tool) as packed:
  prefix_size=min(info.header_offset for info in packed.infolist())
 with tool.open('rb') as i,dest.open('xb') as o:
  prefix=i.read(prefix_size)
  if prefix[:4]!=b'\x7fELF':raise ValueError('Expected matching embedded Soong Python interpreter')
  o.write(prefix)
 with zipfile.ZipFile(tool) as src,zipfile.ZipFile(dest,'a',compression=zipfile.ZIP_DEFLATED) as dst:
  if 'ota_from_target_files.pyc' not in src.namelist() or 'ota_from_target_files.py' in src.namelist():raise ValueError('Unexpected Soong packaged Python tool')
  for info in src.infolist():
   if info.filename!='ota_from_target_files.pyc':copy_entry(src,dst,info)
  dst.writestr('ota_from_target_files.py',patched)
 dest.chmod(0o755)
 return {'embeddedInterpreterPrefixSha256':hashlib.sha256(prefix).hexdigest(),'upstreamBuildMakeCommit':commit,'sourceSha256':hashlib.sha256(content).hexdigest(),'patchedSourceSha256':hashlib.sha256(patched).hexdigest(),'matchingBuiltToolSha256':digest(tool),'adaptedToolSha256':digest(dest),'repair':'gate ublk dynamic-metadata edit on use_dynamic_partitions=true; no system or payload signature bypass'}

def main():
 p=argparse.ArgumentParser();p.add_argument('--pipeline',type=Path,required=True);p.add_argument('--intermediate',type=Path,required=True);p.add_argument('--preparation',type=Path,required=True);p.add_argument('--record',type=Path,required=True);p.add_argument('--target-files',type=Path,required=True);p.add_argument('--host',type=Path,required=True);p.add_argument('--key-base',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--sequence',type=int,required=True);p.add_argument('--version',required=True);p.add_argument('--github-url',default='');a=p.parse_args()
 for name in ('pipeline','intermediate','preparation','record','target_files','host'):
  setattr(a,name,getattr(a,name).resolve(strict=True))
 a.key_base=a.key_base.resolve();a.output=a.output.resolve()
 if a.sequence<=0 or a.output.exists():raise ValueError('Positive target sequence and NEW output required')
 spec=importlib.util.spec_from_file_location('auditor',a.pipeline/'scripts/package-clean-release.py');audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
 audit.audit_inputs(a.preparation,a.record)
 if not (a.key_base.with_suffix('.pem')).is_file():raise ValueError('Separate protected publisher PEM key required')
 a.output.mkdir();stage=a.output/'material';stage.mkdir()
 schemas=a.pipeline/'contracts/format-2';pin=json.loads((schemas/'PIN.json').read_text())
 for name,h in pin['files'].items():
  if digest(schemas/name)!=h:raise ValueError('Native contract bytes differ from pin')
 with zipfile.ZipFile(a.intermediate) as original:
  manifest=json.loads(original.read('manifest.json'));lock=json.loads(original.read(manifest['sourceLock']['path']))
  for image in manifest['payloads']:
   role=image['role'];dest=stage/(role+'.img');unpack(original,image['path'],dest)
   if dest.stat().st_size!=image['bytes'] or digest(dest)!=image['sha256'] or dest.stat().st_size>CAP[role]:raise ValueError('Intermediate build image length/hash/capacity changed')
   image['partitionBytes']=CAP[role]
  # Actual emitted filesystem, not declared Make properties.
  sys=stage/'system-readonly';run([a.host/'bin/fsck.erofs','--extract='+str(sys),stage/'system.img'])
  props={}
  for f in sys.rglob('build.prop'):
   for line in f.read_text(errors='strict').splitlines():
    if line.startswith('ro.kiki.ota.'):
     k,v=line.split('=',1)
     if k in props and props[k]!=v:raise ValueError('Conflicting native properties')
     props[k]=v
  if props.get('ro.kiki.ota.layout')!='gpt-ab-v1' or props.get('ro.kiki.ota.sequence')!=str(a.sequence):raise ValueError('Actual system is not the requested native target sequence')
  cert_candidates=list(sys.rglob('etc/update_engine/kiki-otacerts.zip'))
  if len(cert_candidates)!=1:raise ValueError('Actual native OTA trust store missing/ambiguous')
  expected=(a.record/'device-source/device/kiki/kikiaosp_test/ota/payload.x509.pem').read_bytes()
  with zipfile.ZipFile(cert_candidates[0]) as certs:
   if certs.namelist()!=['payload.x509.pem'] or certs.read('payload.x509.pem')!=expected:raise ValueError('Native engine must authorize ONLY the publisher key, never public testkeys')
  manifest.update(formatVersion=2,runtimeAbi='kiki-arm64-whpx-virgl-gpt-ab-v1',minimumLauncherVersion='0.3.0-alpha',layoutVersion='gpt-ab-v1',requiredFeatures=FEATURES)
  lock['sourceLockVersion']=2;lock['contract']['manifestSchemaSha256']=pin['files']['manifest.schema.json'];lock['contract']['sourceLockSchemaSha256']=pin['files']['source-lock.schema.json'];lock['contract']['revision']=subprocess.check_output(['git','-C',str(a.pipeline),'rev-parse','HEAD']).decode().strip()
  lock_bytes=raw(lock);manifest['sourceLock'].update(bytes=len(lock_bytes),sha256=hashlib.sha256(lock_bytes).hexdigest())
  jsonschema.Draft202012Validator(json.loads((schemas/'manifest.schema.json').read_text())).validate(manifest);jsonschema.Draft202012Validator(json.loads((schemas/'source-lock.schema.json').read_text())).validate(lock)
  baseline=a.output/('KikiAOSP-'+manifest['systemVersion']+'-arm64-ab.zip')
  with zipfile.ZipFile(baseline,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as out:
   for info in original.infolist():
    if info.filename=='manifest.json':out.writestr(info,raw(manifest))
    elif info.filename==manifest['sourceLock']['path']:out.writestr(info,lock_bytes)
    else:copy_entry(original,out,info)
 # Target-files uses our actual audited EMPTY-cmdline header-v4 GPT ramdisk.
 # A generic emulator BOOT image is not silently accepted as the direct ABI.
 target=a.output/'native-target-files.zip'
 with zipfile.ZipFile(a.target_files) as src,zipfile.ZipFile(target,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as dst:
  names=set(src.namelist());parts=src.read('META/ab_partitions.txt').decode().split()
  if set(parts)!=set(CAP) or len(parts)!=3:raise ValueError('Full payload must touch ONLY boot/system/vendor, never userdata/misc')
  image_adaptation={}
  for role in ('system','vendor'):
   temp=stage/(role+'-target.img');unpack(src,'IMAGES/'+role+'.img',temp)
   original_hash=digest(temp);canonical_hash=digest(stage/(role+'.img'))
   differences=[]
   if original_hash!=canonical_hash:
    canonical=sys if role=='system' else stage/'vendor-readonly'
    if role=='vendor':run([a.host/'bin/fsck.erofs','--extract='+str(canonical),stage/'vendor.img'])
    reconstructed=stage/(role+'-target-readonly');run([a.host/'bin/fsck.erofs','--extract='+str(reconstructed),temp])
    x,y=filesystem_tree(canonical),filesystem_tree(reconstructed)
    differences=[n for n in sorted(set(x)|set(y)) if x.get(n)!=y.get(n)]
    # AOSP target-files reconstruction adds these 32-bit DLKM compatibility
    # entries even for our 64-bit-only embedded-system-dlkm direct target.
    # Permit exactly that observed reconstruction effect, never changed APKs,
    # libraries, properties, permissions, missing baseline files or other links.
    synthetic={'system/lib':(0o755,'dir'),'system/lib/modules':(0o777,'link:/system_dlkm/lib/modules')}
    if role=='system':
     if any(n in x or y.get(n)!=synthetic.get(n) for n in differences):raise ValueError('Unexpected reconstructed system filesystem content/mode/link differences: '+str(differences))
    elif differences:raise ValueError('Unexpected reconstructed vendor filesystem content/mode/link differences: '+str(differences))
   image_adaptation[role]={'originalTargetImageSha256':original_hash,'canonicalAuditedImageSha256':canonical_hash,'reconstructedFilesystemDifferences':differences}
   temp.unlink()
  for info in src.infolist():
   if info.filename in ('IMAGES/boot.img','IMAGES/system.img','IMAGES/vendor.img'):
    dst.write(stage/(Path(info.filename).stem+'.img'),info.filename,compress_type=zipfile.ZIP_DEFLATED)
   else:copy_entry(src,dst,info)
  if 'IMAGES/boot.img' not in names:dst.write(stage/'boot.img','IMAGES/boot.img',compress_type=zipfile.ZIP_DEFLATED)
 jdk=Path(json.loads((a.record/'build-audit.json').read_text())['aosp'])/'prebuilts/jdk/jdk21/linux-x86'
 if not (jdk/'bin/java').is_file():raise ValueError('Matching pinned AOSP JDK missing')
 env=dict(os.environ,PATH=str(a.host/'bin')+':'+str(jdk/'bin')+':/usr/bin:/bin',JAVA_HOME=str(jdk),LD_LIBRARY_PATH=str(a.host/'lib64'))
 native=a.output/'android-native-full.ota.zip'
 adapted_tool=a.output/'physical-ab-ota-tool.pyz';tool_adaptation=physical_ab_tool(a.host,a.record,adapted_tool)
 run([adapted_tool,'-p',a.host,'--no_signing','--skip_postinstall','--max_threads=8','-k',a.key_base,target,native],env)
 with zipfile.ZipFile(native) as n:
  unpack(n,'payload.bin',stage/'payload.bin');properties=n.read('payload_properties.txt');metadata=n.read('META-INF/com/android/metadata')
 with (stage/'payload.bin').open('rb') as f:
  if f.read(4)!=b'CrAU':raise ValueError('Not an Android payload')
 run([a.host/'bin/delta_generator','--in_file='+str(stage/'payload.bin'),'--public_key='+str(a.record/'device-source/device/kiki/kikiaosp_test/ota/update-payload-key.pub.pem')],env)
 cat={'kind':'org.kiki.ota.full','format':1,'device':'kikiaosp_test','layout':'gpt-ab-v1','android_major':17,'sequence':a.sequence,'version':a.version,'payload_sha256':digest(stage/'payload.bin'),'payload_bytes':(stage/'payload.bin').stat().st_size,'ota_url':a.github_url}
 (a.output/'KikiAOSP-ota.json').write_bytes(raw(cat));signature=a.output/'KikiAOSP-ota.sig';run(['openssl','dgst','-sha256','-sign',a.key_base.with_suffix('.pem'),'-out',signature,a.output/'KikiAOSP-ota.json'])
 if signature.stat().st_size!=256:raise ValueError('Unexpected publisher RSA signature size')
 wrapper=a.output/('KikiAOSP-'+manifest['systemVersion']+'-full.ota.zip')
 with zipfile.ZipFile(wrapper,'x',compression=zipfile.ZIP_STORED) as z:
  z.write(stage/'payload.bin','payload.bin');z.writestr('payload_properties.txt',properties);z.writestr('META-INF/com/android/metadata',metadata);z.writestr('kiki-ota.json',raw(cat));z.write(signature,'kiki-ota.sig')
 proof={'kind':'org.kiki.native-ota-build-proof','sequence':a.sequence,'nonrelease':not a.github_url,'sourceIntermediateSha256':digest(a.intermediate),'originalTargetFilesSha256':digest(a.target_files),'adaptedTargetFilesSha256':digest(target),'deviceBuiltCommit':lock['device']['commit'],'contractPipelineCommit':lock['contract']['revision'],'partitionRoles':list(CAP),'physicalAbHostToolAdaptation':tool_adaptation,'filesystemImageAdaptation':image_adaptation,'kernelInputGraph':json.loads((a.intermediate.parent/'package-audit.json').read_text())['kernelGraph'],'matchingJavaSha256':digest(jdk/'bin/java'),'userdataTouched':False,'baselineSha256':digest(baseline),'otaSha256':digest(wrapper),'payloadSha256':cat['payload_sha256'],'tools':{name:digest(a.host/'bin'/name) for name in ('ota_from_target_files','brillo_update_payload','delta_generator')}}
 (a.output/'native-ota-proof.json').write_bytes(raw(proof));print(json.dumps(proof,indent=2),flush=True)

if __name__=='__main__':main()
