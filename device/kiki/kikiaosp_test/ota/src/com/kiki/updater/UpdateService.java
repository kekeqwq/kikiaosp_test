// SPDX-License-Identifier: Apache-2.0
package com.kiki.updater;

import android.app.*;
import android.content.*;
import android.os.*;
import android.util.Base64;
import org.json.*;
import javax.net.ssl.HttpsURLConnection;
import java.io.*;
import java.net.*;
import java.security.*;
import java.security.spec.X509EncodedKeySpec;
import java.util.*;
import java.util.concurrent.*;
import java.util.zip.*;

/** Both frontends submit to Android's native UpdateEngine, never to a second flasher. */
public final class UpdateService extends android.app.Service {
 private final ExecutorService worker=Executors.newSingleThreadExecutor();
 private final UpdateEngine engine=new UpdateEngine();
 private volatile boolean installing; private JSONObject candidate; private File stageFile;
 private void discardStage(File f){try{if(f==null)return;File canonical=f.getCanonicalFile(),parent=canonical.getParentFile();if(parent!=null&&getFilesDir().getCanonicalFile().equals(parent.getParentFile())&&parent.getName().matches("ota-[0-9a-f-]{36}")){canonical.delete();parent.delete();}}catch(Exception e){android.util.Log.w("KikiUpdater","Stage cleanup failed",e);}}
 private void clearPending(){discardStage(new File(getSharedPreferences(PREF,0).getString("stage","/invalid")));getSharedPreferences(PREF,0).edit().remove("stage").putLong("pendingSequence",0).putBoolean("rebootReady",false).commit();}
 private static final String PREF="ota",API="https://api.github.com/repos/kekeqwq/kikiaosp_test/releases?per_page=30";
 private static final long MAX=8L*1024*1024*1024;
 public static String status(Context c){return c.getSharedPreferences(PREF,0).getString("status","Updates have not been checked. Current system: "+Build.DISPLAY);}
 private void state(String s,int nativeState){
  getSharedPreferences(PREF,0).edit().putString("status",s).apply();
  PersistableBundle b=new PersistableBundle();b.putInt(SystemUpdateManager.KEY_STATUS,nativeState);b.putString(SystemUpdateManager.KEY_TITLE,Build.DISPLAY);
  ((SystemUpdateManager)getSystemService(SYSTEM_UPDATE_SERVICE)).updateSystemUpdateInfo(b);
 }
 private void completeInstalled(){long pending=getSharedPreferences(PREF,0).getLong("pendingSequence",0);
  if(pending>0&&SystemProperties.getLong("ro.kiki.ota.sequence",0)>=pending&&SystemProperties.get("sys.kiki.ota.boot_verified").equals("1")){getSharedPreferences(PREF,0).edit().putLong("acceptedSequence",pending).commit();clearPending();state("Update complete. Current system: "+Build.DISPLAY,SystemUpdateManager.STATUS_IDLE);}}
 public void onCreate(){super.onCreate();completeInstalled();
  if(SystemProperties.getBoolean("ro.boot.kiki_ota_rollback",false)){engine.resetStatus();clearPending();state("The updated slot did not pass startup checks. The previous system has been restored without formatting user data. See the logs for details.",SystemUpdateManager.STATUS_IDLE);}
  NotificationManager n=getSystemService(NotificationManager.class);n.createNotificationChannel(new NotificationChannel("ota","System updates",NotificationManager.IMPORTANCE_LOW));
  startForeground(3,new Notification.Builder(this,"ota").setSmallIcon(android.R.drawable.stat_sys_download).setContentTitle("Kiki System Update").setContentText("Signed full OTA updates, keeping your data").build());
  engine.bind(new UpdateEngineCallback(){
   public void onStatusUpdate(int s,float p){
    if(s==UpdateEngine.UpdateStatusConstants.UPDATED_NEED_REBOOT){installing=false;getSharedPreferences(PREF,0).edit().putBoolean("rebootReady",true).commit();state("The update is installed in the inactive slot. Restart to finish updating.",SystemUpdateManager.STATUS_WAITING_REBOOT);}
    else if(s==UpdateEngine.UpdateStatusConstants.DOWNLOADING||s==UpdateEngine.UpdateStatusConstants.VERIFYING||s==UpdateEngine.UpdateStatusConstants.FINALIZING){installing=true;state("Native update engine: stage "+s+", "+Math.round(p*100)+"%",SystemUpdateManager.STATUS_IN_PROGRESS);}
   }
   public void onPayloadApplicationComplete(int code){if(code==0)SystemProperties.set("sys.kiki.storage.refresh",Long.toString(System.nanoTime()));if(code!=0){installing=false;clearPending();state("Installation failed (update_engine="+code+"). The current system is still available. Check the logs before retrying.",SystemUpdateManager.STATUS_IDLE);}}
  },new Handler(getMainLooper()));
 }
 public int onStartCommand(Intent i,int flags,int id){if(i==null)return START_NOT_STICKY;final String cmd=i.getStringExtra("command"),path=i.getStringExtra("path");
  worker.execute(()->{try{
   if(cmd.equals("resume")){for(int wait=0;wait<60&&!SystemProperties.get("sys.kiki.ota.boot_verified").equals("1");wait++)Thread.sleep(1000);completeInstalled();long pending=getSharedPreferences(PREF,0).getLong("pendingSequence",0);if(pending>current()&&!installing&&!getSharedPreferences(PREF,0).getBoolean("rebootReady",false)){File f=new File(getSharedPreferences(PREF,0).getString("stage","/invalid"));if(!f.getCanonicalFile().getParentFile().getParentFile().equals(getFilesDir().getCanonicalFile()))throw new IOException("Invalid persistent update transaction path");apply(f,null);}}
   else if(cmd.equals("check")){if(installing||getSharedPreferences(PREF,0).getBoolean("rebootReady",false))throw new IOException("An update is installing or waiting for restart; another update cannot be submitted");check();}
   else if(cmd.equals("install")){if(candidate==null)throw new IOException("Check for updates first");download(candidate);}
   else if(cmd.equals("apply")){applyOffline(path);}
   else if(cmd.equals("reboot")){reboot();}
   else throw new IOException("Unknown update command");
  }catch(Exception e){android.util.Log.e("KikiUpdater","OTA command failed",e);if(!installing&&!getSharedPreferences(PREF,0).getBoolean("rebootReady",false)){discardStage(stageFile);clearPending();state("Update not completed: "+e.getMessage(),SystemUpdateManager.STATUS_IDLE);}}});return START_NOT_STICKY;
 }
 public IBinder onBind(Intent i){return null;}
 public void onDestroy(){engine.unbind();worker.shutdown();super.onDestroy();}
 private PublicKey key()throws Exception{try(InputStream in=getResources().openRawResource(com.kiki.updater.R.raw.ota_public)){return KeyFactory.getInstance("RSA").generatePublic(new X509EncodedKeySpec(bounded(in,4096)));}}
 private JSONObject authenticate(byte[] raw,byte[] sig)throws Exception{
  if(raw.length>65536||sig.length!=256)throw new IOException("Invalid signed metadata length");Signature v=Signature.getInstance("SHA256withRSA");v.initVerify(key());v.update(raw);if(!v.verify(sig))throw new IOException("The OTA signature is not from a trusted Kiki publisher");
  // JSONObject normally accepts duplicate keys; reject them before interpreting security metadata.
  String text=new String(raw,java.nio.charset.StandardCharsets.UTF_8);Set<String> keys=new HashSet<>();java.util.regex.Matcher m=java.util.regex.Pattern.compile("\\\"([^\\\"\\\\]+)\\\"\\s*:").matcher(text);while(m.find())if(!keys.add(m.group(1)))throw new IOException("Duplicate OTA metadata field");
  JSONObject j=new JSONObject(text);Set<String> allowed=new HashSet<>(Arrays.asList("kind","format","device","layout","android_major","sequence","version","payload_sha256","payload_bytes","ota_url"));
  Iterator<String> it=j.keys();while(it.hasNext())if(!allowed.remove(it.next()))throw new IOException("Unknown OTA metadata field");if(!allowed.isEmpty())throw new IOException("Missing OTA metadata field");
  if(!j.getString("kind").equals("org.kiki.ota.full")||j.getInt("format")!=1||!j.getString("device").equals("kikiaosp_test")||!j.getString("layout").equals("gpt-ab-v1")||j.getInt("android_major")!=17)throw new IOException("Incompatible device, disk layout, or Android version");
  if(!j.getString("payload_sha256").matches("[0-9a-f]{64}")||j.getLong("payload_bytes")<=0||j.getLong("payload_bytes")>MAX||j.getLong("sequence")<=0)throw new IOException("Invalid OTA integrity constraints");
  return j;
 }
 private long current(){return Math.max(SystemProperties.getLong("ro.kiki.ota.sequence",1),getSharedPreferences(PREF,0).getLong("acceptedSequence",0));}
 private void check()throws Exception{
  state("Checking official GitHub Releases...",SystemUpdateManager.STATUS_IDLE);JSONArray releases=new JSONArray(new String(fetch(API,1024*1024),"UTF-8"));JSONObject best=null;int rejected=0;
  for(int r=0;r<releases.length();r++){JSONObject release=releases.getJSONObject(r);if(release.optBoolean("draft"))continue;JSONArray assets=release.getJSONArray("assets");String meta=null,sig=null;
   for(int a=0;a<assets.length();a++){JSONObject asset=assets.getJSONObject(a);if(asset.getString("name").equals("KikiAOSP-ota.json"))meta=asset.getString("browser_download_url");if(asset.getString("name").equals("KikiAOSP-ota.sig"))sig=asset.getString("browser_download_url");}
   if(meta==null||sig==null)continue;
   try{JSONObject j=authenticate(fetch(meta,65536),fetch(sig,256));releaseUrl(j.getString("ota_url"));if(j.getLong("sequence")>current()&&(best==null||j.getLong("sequence")>best.getLong("sequence")))best=j;}catch(Exception e){rejected++;android.util.Log.w("KikiUpdater","Rejected release metadata",e);}
  }
  candidate=best;if(best!=null)state("Update available: "+best.getString("version")+"\nDownload and install to update without erasing your data.",SystemUpdateManager.STATUS_WAITING_DOWNLOAD);
  else if(rejected>0)throw new IOException("Some release metadata could not be verified; unable to confirm that the system is up to date");
  else state("Your system is up to date.\nCurrent sequence: "+current()+" (no newer compatible, signed OTA found)",SystemUpdateManager.STATUS_IDLE);
 }
 private static void releaseUrl(String s)throws Exception{URI u=new URI(s);if(!u.getScheme().equals("https")||!u.getHost().equals("github.com")||!u.getPath().startsWith("/kekeqwq/kikiaosp_test/releases/download/")||u.getUserInfo()!=null||u.getFragment()!=null||u.getPort()!=-1)throw new IOException("The OTA release URL is not allowed");}
 private HttpsURLConnection connection(String address)throws Exception{
  for(int redirects=0;redirects<6;redirects++){URL u=new URL(address);String h=u.getHost();if(!u.getProtocol().equals("https")||!(h.equals("api.github.com")||h.equals("github.com")||h.endsWith(".githubusercontent.com"))||u.getUserInfo()!=null)throw new IOException("The update URL is not an allowed HTTPS GitHub address");
   HttpsURLConnection c=(HttpsURLConnection)u.openConnection();c.setConnectTimeout(15000);c.setReadTimeout(30000);c.setInstanceFollowRedirects(false);c.setRequestProperty("User-Agent","KikiUpdater/0.3");c.setRequestProperty("Accept","application/vnd.github+json");int code=c.getResponseCode();
   if(code>=300&&code<400){String loc=c.getHeaderField("Location");c.disconnect();if(loc==null)throw new IOException("Invalid download redirect");address=new URL(u,loc).toString();continue;}
   if(code!=200){c.disconnect();throw new IOException("GitHub HTTP "+code);}return c;
  }throw new IOException("Too many download redirects");
 }
 private byte[] fetch(String url,int limit)throws Exception{HttpsURLConnection c=connection(url);try(InputStream in=c.getInputStream()){return bounded(in,limit);}finally{c.disconnect();}}
 private static byte[] bounded(InputStream in,int limit)throws Exception{ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] b=new byte[8192];for(int n;(n=in.read(b))!=-1;){if(out.size()+n>limit)throw new IOException("Metadata exceeds the size limit");out.write(b,0,n);}return out.toByteArray();}
 private File newStage()throws Exception{File d=new File(getFilesDir(),"ota-"+UUID.randomUUID());if(!d.mkdir())throw new IOException("Could not create an isolated update directory");stageFile=new File(d,"update.ota.zip");return stageFile;}
 private void download(JSONObject j)throws Exception{
  if(installing||getSharedPreferences(PREF,0).getBoolean("rebootReady",false))throw new IOException("An update is already installing or waiting for restart");File f=newStage();releaseUrl(j.getString("ota_url"));HttpsURLConnection c=connection(j.getString("ota_url"));long total=0;
  try(InputStream in=c.getInputStream();FileOutputStream out=new FileOutputStream(f)){byte[] b=new byte[65536];for(int n;(n=in.read(b))!=-1;){total+=n;if(total>MAX)throw new IOException("The update package exceeds the size limit");out.write(b,0,n);if(total%(16*1024*1024)<65536)state("Downloading: "+(total/(1024*1024))+" MiB",SystemUpdateManager.STATUS_WAITING_DOWNLOAD);}out.getFD().sync();}finally{c.disconnect();}
  apply(f,j);
 }
 private void applyOffline(String path)throws Exception{
  if(path==null||!path.matches("/data/local/tmp/kiki-ota/incoming-[0-9a-f-]{36}\\.ota\\.zip"))throw new IOException("The OTA import path does not belong to this instance's inbox");if(installing||getSharedPreferences(PREF,0).getBoolean("rebootReady",false))throw new IOException("An update is already installing or waiting for restart");
  File src=new File(path);if(!src.getCanonicalPath().equals(path)||src.length()<=0||src.length()>MAX)throw new IOException("Invalid offline update package");File f=newStage();
  try(FileInputStream in=new FileInputStream(src);FileOutputStream out=new FileOutputStream(f)){byte[] b=new byte[65536];long size=0;for(int n;(n=in.read(b))!=-1;){size+=n;if(size>MAX)throw new IOException("The package exceeds the size limit");out.write(b,0,n);}out.getFD().sync();}
  SystemProperties.set("sys.kiki.ota.imported",path.substring(path.lastIndexOf("incoming-")+9,path.length()-8));
  apply(f,null);
 }
 private void apply(File file,JSONObject expected)throws Exception{
  state("Verifying the signature and complete payload...",SystemUpdateManager.STATUS_WAITING_INSTALL);
  try(ZipFile zip=new ZipFile(file)){
   Set<String> names=new HashSet<>();Enumeration<? extends ZipEntry> entries=zip.entries();while(entries.hasMoreElements()){String name=entries.nextElement().getName();if(!names.add(name)||!(name.equals("payload.bin")||name.equals("payload_properties.txt")||name.equals("kiki-ota.json")||name.equals("kiki-ota.sig")||name.equals("META-INF/com/android/metadata")))throw new IOException("Duplicate or unexpected ZIP entry");}
   if(names.size()!=5)throw new IOException("Incomplete full OTA package");JSONObject j=authenticate(bounded(zip.getInputStream(zip.getEntry("kiki-ota.json")),65536),bounded(zip.getInputStream(zip.getEntry("kiki-ota.sig")),256));
   if(expected!=null&&!expected.toString().equals(j.toString()))throw new IOException("The downloaded package does not match the verified release metadata");if(j.getLong("sequence")<=current())throw new IOException("Duplicate updates and downgrades are not allowed");
   ZipEntry payload=zip.getEntry("payload.bin");if(payload.getMethod()!=ZipEntry.STORED||payload.getSize()!=j.getLong("payload_bytes"))throw new IOException("The payload must be stored uncompressed and match the declared size");
   MessageDigest hash=MessageDigest.getInstance("SHA-256");long read=0;try(InputStream in=zip.getInputStream(payload)){byte[] b=new byte[65536];for(int n;(n=in.read(b))!=-1;){read+=n;if(read>j.getLong("payload_bytes"))throw new IOException("The payload exceeds its declared size");hash.update(b,0,n);}}
   if(read!=j.getLong("payload_bytes")||!hex(hash.digest()).equals(j.getString("payload_sha256")))throw new IOException("The payload SHA-256 does not match");
   String properties=new String(bounded(zip.getInputStream(zip.getEntry("payload_properties.txt")),8192),"UTF-8");List<String> headers=new ArrayList<>();Set<String> props=new HashSet<>();for(String line:properties.split("\n")){if(line.isEmpty())continue;String[] pair=line.split("=",2);if(pair.length!=2||!props.add(pair[0])||!Arrays.asList("FILE_HASH","FILE_SIZE","METADATA_HASH","METADATA_SIZE").contains(pair[0]))throw new IOException("Invalid payload properties");headers.add(line);}
   if(props.size()!=4||!properties.contains("FILE_HASH="+Base64.encodeToString(hashOf(file,zip,payload),Base64.NO_WRAP)))throw new IOException("The payload properties and hash do not match");
   long offset=payloadOffset(file,payload.getSize());getSharedPreferences(PREF,0).edit().putLong("pendingSequence",j.getLong("sequence")).putString("stage",file.getAbsolutePath()).commit();
   headers.add("SWITCH_SLOT_ON_REBOOT=1");headers.add("RUN_POST_INSTALL=0");installing=true;try{engine.applyPayload("file://"+file.getAbsolutePath(),offset,payload.getSize(),headers.toArray(new String[0]));}catch(RuntimeException e){installing=false;clearPending();throw e;}
  }
 }
 private byte[] hashOf(File f,ZipFile z,ZipEntry e)throws Exception{MessageDigest d=MessageDigest.getInstance("SHA-256");try(InputStream in=z.getInputStream(e)){byte[] b=new byte[65536];for(int n;(n=in.read(b))!=-1;)d.update(b,0,n);}return d.digest();}
 private long payloadOffset(File f,long size)throws Exception{try(RandomAccessFile in=new RandomAccessFile(f,"r")){long p=0;while(p+30<in.length()){in.seek(p);byte[] h=new byte[30];in.readFully(h);if(le(h,0,4)!=0x04034b50L)break;long bytes=le(h,18,4);int nl=(int)le(h,26,2),el=(int)le(h,28,2);if(nl>128||el>4096||(le(h,6,2)&9)!=0)throw new IOException("Unsupported ZIP flags or field lengths");byte[] name=new byte[nl];in.readFully(name);long start=p+30+nl+el;if(new String(name,"UTF-8").equals("payload.bin")){if(bytes!=size||le(h,8,2)!=0||start+size>in.length())throw new IOException("Invalid payload offset or size");return start;}p=start+bytes;}throw new IOException("Could not locate the stored payload");}}
 private static long le(byte[] b,int p,int n){long v=0;for(int i=0;i<n;i++)v|=(long)(b[p+i]&255)<<(i*8);return v;}
 private static String hex(byte[] b){StringBuilder s=new StringBuilder();for(byte x:b)s.append(String.format(java.util.Locale.ROOT,"%02x",x&255));return s.toString();}
 private void reboot()throws Exception{if(!getSharedPreferences(PREF,0).getBoolean("rebootReady",false))throw new IOException("There is no installed update waiting for restart");
  // Host owns the virtual bootloader. A plain QEMU RESET reloads the old -kernel.
  SystemProperties.set("sys.kiki.ota.reboot","1");state("Shutting down safely and switching system slots...",SystemUpdateManager.STATUS_WAITING_REBOOT);
 }
}
