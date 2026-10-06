#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
from pathlib import Path
import subprocess,tempfile
repo=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='kiki-storage-test-') as tmp:
 t=Path(tmp)
 (t/'native.cpp').write_text(r'''
#include "StorageImageSizes.h"
#include <array>
#include <cassert>
#include <iostream>
int main(){using namespace kiki_storage;std::array<unsigned char,4096> h{};
auto put=[&](size_t at,uint32_t n){for(int i=0;i<4;i++)h[at+i]=n>>(8*i);};
auto reject=[&](auto f){bool rejected=false;try{f();}catch(const std::exception&){rejected=true;}assert(rejected);};
memcpy(h.data(),"ANDROID!",8);put(8,35613184);put(12,1507744);put(20,1584);put(40,4);
assert(bootBytes(h.data(),4096,64ULL<<20)==37130240);reject([&]{bootBytes(h.data(),1500,64ULL<<20);});
put(1580,1);reject([&]{bootBytes(h.data(),4096,64ULL<<20);});put(1580,0);
put(8,64U<<20);reject([&]{bootBytes(h.data(),4096,64ULL<<20);});put(8,0);reject([&]{bootBytes(h.data(),4096,64ULL<<20);});
h.fill(0);put(1024,0xe0f5e1e2);h[1036]=12;put(1060,228483);
assert(erofsBytes(h.data(),4096,4ULL<<30)==935866368);put(1060,0);reject([&]{erofsBytes(h.data(),4096,4ULL<<30);});
put(1060,0xffffffff);reject([&]{erofsBytes(h.data(),4096,4ULL<<30);});put(1060,228483);put(1104,0x80);reject([&]{erofsBytes(h.data(),4096,4ULL<<30);});
put(1104,0);h[1036]=16;reject([&]{erofsBytes(h.data(),4096,4ULL<<30);});
std::cout<<"PASS native header bounds, unequal-image measured sizes, unsigned boot/EROFS invalid-header negatives\n";}
''')
 subprocess.run(['c++','-std=c++17','-Wall','-Wextra','-Werror','-I',str(repo/'device/kiki/kikiaosp_test/ota/storage'),str(t/'native.cpp'),'-o',str(t/'native')],check=True)
 subprocess.run([str(t/'native')],check=True)
 android=t/'android/os';android.mkdir(parents=True)
 (android/'SystemProperties.java').write_text('''package android.os; import java.util.HashMap; public class SystemProperties {public static final HashMap<String,String> values=new HashMap<>(); public static String get(String k){return values.getOrDefault(k,"");} public static long getLong(String k,long d){try{return Long.parseLong(get(k));}catch(Exception e){return d;}}}''')
 (android/'Environment.java').write_text('''package android.os; import java.io.File; public class Environment {public static long total,free,usable; public static File getDataDirectory(){return new File("/isolated-data"){public long getTotalSpace(){return total;} public long getFreeSpace(){return free;} public long getUsableSpace(){return usable;}};}}''')
 (t/'Test.java').write_text('''import android.os.*; import com.android.settingslib.deviceinfo.KikiStorageAccounting; public class Test {static void expect(long a,long b){if(a!=b)throw new AssertionError(a+" != "+b);} public static void main(String[] args){long GiB=1L<<30,disk=32*GiB; Environment.total=23*GiB;Environment.free=22*GiB;Environment.usable=22*GiB; expect(KikiStorageAccounting.getUsedBytes(disk,22*GiB),10*GiB);SystemProperties.values.put("ro.kiki.ota.layout","gpt-ab-v1");SystemProperties.values.put("sys.kiki.storage.status","ready");SystemProperties.values.put("sys.kiki.storage.disk",""+disk);SystemProperties.values.put("sys.kiki.storage.data",""+Environment.total);SystemProperties.values.put("sys.kiki.storage.images",""+(2*GiB));expect(KikiStorageAccounting.getUsedBytes(disk,22*GiB),3*GiB);expect(KikiStorageAccounting.getSystemBytes(disk,9*GiB),2*GiB);expect(KikiStorageAccounting.getReservedBytes(disk),7*GiB);expect(KikiStorageAccounting.getWritableBytes(disk),22*GiB);expect(KikiStorageAccounting.getUsedBytes(disk,22*GiB)+KikiStorageAccounting.getReservedBytes(disk)+KikiStorageAccounting.getWritableBytes(disk),disk);Environment.usable=21*GiB;expect(KikiStorageAccounting.getReservedBytes(disk),8*GiB);expect(KikiStorageAccounting.getUsedBytes(disk,99*GiB),3*GiB);SystemProperties.values.put("sys.kiki.storage.disk",""+(64*GiB));expect(KikiStorageAccounting.getReservedBytes(disk),-1);SystemProperties.values.put("sys.kiki.storage.disk",""+disk);SystemProperties.values.put("sys.kiki.storage.images",""+(31*GiB));expect(KikiStorageAccounting.getReservedBytes(disk),-1);SystemProperties.values.put("sys.kiki.storage.images",""+(2*GiB));SystemProperties.values.put("sys.kiki.storage.status","unavailable");expect(KikiStorageAccounting.getUsedBytes(disk,22*GiB),10*GiB);expect(KikiStorageAccounting.getReservedBytes(disk),-1);System.out.println("PASS Java used/system/reserved/writable partition identity, >2GiB arithmetic, old-layout/unavailable/overflow negatives; no writable API inflation");}}''')
 jdk=Path('/home/keke/aosp-release-0.3-ota-r7/prebuilts/jdk/jdk21/linux-x86/bin')
 subprocess.run([str(jdk/'javac'),'-d',str(t),str(android/'Environment.java'),str(android/'SystemProperties.java'),str(repo/'overlays/frameworks/base/packages/SettingsLib/src/com/android/settingslib/deviceinfo/KikiStorageAccounting.java'),str(t/'Test.java')],check=True)
 subprocess.run([str(jdk/'java'),'-cp',str(t),'Test'],check=True)
