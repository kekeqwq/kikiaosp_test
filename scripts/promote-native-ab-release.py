#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Promote the exact tested sequence4 FULL payload, never rebuild or flash it.

Requires explicit release identity, prior proof and private external signer.
Only public catalog/signature/container metadata change; native payload and
canonical format-2 baseline bytes remain exactly those actually tested.
"""
import argparse,hashlib,json,os,shutil,subprocess,tempfile,zipfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for n in ('candidate','output','key-base','public-key','delta-generator'):p.add_argument('--'+n,type=Path,required=True)
p.add_argument('--authorize-version',required=True)
a=p.parse_args()
if a.authorize_version!='0.3.0-alpha':raise ValueError('Only explicit user-authorized 0.3 Alpha promotion is supported')
source=a.candidate.resolve();output=a.output.resolve();key=a.key_base.resolve()
if key.parent!=Path('/home/keke/.local/share/kiki-ota-signing-alpha03') or key.with_suffix('.pem').stat().st_mode&0o077:raise ValueError('Private publisher signer identity/permissions invalid')
sha=lambda f:hashlib.file_digest(f.open('rb'),'sha256').hexdigest()
proof=json.loads((source/'native-ota-proof.json').read_text())
if proof['kind']!='org.kiki.native-ota-build-proof' or proof['sequence']!=4 or proof['deviceBuiltCommit']!='4b3e71fca9d63c1f8ce3be5430444c7c52290971' or proof['userdataTouched'] is not False:raise ValueError('Unexpected actually tested candidate')
baseline=source/'KikiAOSP-0.3.0-alpha-arm64-ab.zip';old=source/'KikiAOSP-0.3.0-alpha-full.ota.zip'
if sha(baseline)!=proof['baselineSha256'] or sha(old)!=proof['otaSha256']:raise ValueError('Tested source bytes changed')
output.mkdir(exist_ok=False,parents=False)
with zipfile.ZipFile(old) as z:
 names=z.namelist()
 if len(names)!=5 or set(names)!={'payload.bin','payload_properties.txt','kiki-ota.json','kiki-ota.sig','META-INF/com/android/metadata'} or z.getinfo('payload.bin').compress_type!=zipfile.ZIP_STORED:raise ValueError('Unexpected native wrapper')
 with z.open('payload.bin') as f:
  payload_hash=hashlib.file_digest(f,'sha256').hexdigest()
 if payload_hash!=proof['payloadSha256']:raise ValueError('Native signed payload changed')
 # Re-verify independently with the matching audited native host tool.
 if sha(a.delta_generator)!=proof['tools']['delta_generator']:raise ValueError('Matching signature verifier changed')
 with tempfile.TemporaryDirectory(prefix='public-native-verify-',dir=output.parent) as temp:
  payload=Path(temp)/'payload.bin'
  with z.open('payload.bin') as f,payload.open('wb') as out:shutil.copyfileobj(f,out,1024*1024)
  subprocess.run([str(a.delta_generator),'--in_file='+str(payload),'--public_key='+str(a.public_key.resolve())],check=True)
 catalog=json.loads(z.read('kiki-ota.json'))
 if catalog['sequence']!=4 or catalog['payload_sha256']!=payload_hash or catalog['ota_url']!='' or catalog['device']!='kikiaosp_test' or catalog['layout']!='gpt-ab-v1' or catalog['android_major']!=17:raise ValueError('Not the bounded private regression catalog')
 catalog['version']='0.3.0-alpha'
 catalog['ota_url']='https://github.com/kekeqwq/kikiaosp_test/releases/download/v0.3.0-alpha/KikiAOSP-0.3.0-alpha-full.ota.zip'
 raw=(json.dumps(catalog,sort_keys=True,separators=(',',':'))+'\n').encode()
 metadata=output/'KikiAOSP-ota.json';signature=output/'KikiAOSP-ota.sig';metadata.write_bytes(raw)
 subprocess.run(['openssl','dgst','-sha256','-sign',str(key.with_suffix('.pem')),'-out',str(signature),str(metadata)],check=True)
 subprocess.run(['openssl','dgst','-sha256','-verify',str(a.public_key.resolve()),'-signature',str(signature),str(metadata)],check=True)
 public=output/old.name
 with zipfile.ZipFile(public,'x',compression=zipfile.ZIP_STORED,allowZip64=True) as target:
  for name in names:
   if name=='kiki-ota.json':target.writestr(name,raw)
   elif name=='kiki-ota.sig':target.writestr(name,signature.read_bytes())
   else:
    entry=zipfile.ZipInfo(name,date_time=(1980,1,1,0,0,0));entry.compress_type=zipfile.ZIP_STORED;entry.external_attr=0o100644<<16
    with z.open(name) as f,target.open(entry,'w',force_zip64=False) as out:shutil.copyfileobj(f,out,1024*1024)
with zipfile.ZipFile(public) as z,zipfile.ZipFile(old) as prior:
 for name in ('payload.bin','payload_properties.txt','META-INF/com/android/metadata'):
  with z.open(name) as x,prior.open(name) as y:
   if hashlib.file_digest(x,'sha256').digest()!=hashlib.file_digest(y,'sha256').digest():raise ValueError('Promotion changed native content')
 if z.read('kiki-ota.json')!=raw or z.read('kiki-ota.sig')!=signature.read_bytes():raise ValueError('Published catalog/container mismatch')
os.link(baseline,output/baseline.name)
public_proof=dict(proof,nonrelease=False,version='0.3.0-alpha',otaSha256=sha(public),catalogSha256=sha(metadata),catalogSignatureSha256=sha(signature),nativePublisherSignatureReverified=True,candidateOtaSha256=proof['otaSha256'],promotion='Only signed public catalog URL/version and wrapper headers; native payload/properties/Android metadata and baseline byte-identical',promotionScriptSha256=sha(Path(__file__)),userOnlineOtaAcceptance='Deferred to future 0.4; not claimed passed')
(output/'native-ota-proof.json').write_text(json.dumps(public_proof,indent=2)+'\n')
print(json.dumps({'publicWrapperSha256':sha(public),'publicWrapperBytes':public.stat().st_size,'baselineSha256':sha(baseline),'unchangedNativePayloadSha256':payload_hash,'sequence':4}),flush=True)
