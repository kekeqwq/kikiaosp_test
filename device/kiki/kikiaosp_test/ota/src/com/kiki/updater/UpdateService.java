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
 private void discardStage(File f){try{if(f!=null&&f.getCanonicalFile().getParentFile().getParentFile().equals(getFilesDir().getCanonicalFile())&&f.getParentFile().getName().matches("ota-[0-9a-f-]{36}")){f.delete();f.getParentFile().delete();}}catch(Exception e){android.util.Log.w("KikiUpdater","Stage cleanup failed",e);}}
 private void clearPending(){discardStage(new File(getSharedPreferences(PREF,0).getString("stage","/invalid")));getSharedPreferences(PREF,0).edit().remove("stage").putLong("pendingSequence",0).putBoolean("rebootReady",false).commit();}
 private static final String PREF="ota",API="https://api.github.com/repos/kekeqwq/kikiaosp_test/releases?per_page=30";
 private static final long MAX=8L*1024*1024*1024;
 public static String status(Context c){return c.getSharedPreferences(PREF,0).getString("status","尚未检查更新。当前系统："+Build.DISPLAY);}
 private void state(String s,int nativeState){
  getSharedPreferences(PREF,0).edit().putString("status",s).apply();
  PersistableBundle b=new PersistableBundle();b.putInt(SystemUpdateManager.KEY_STATUS,nativeState);b.putString(SystemUpdateManager.KEY_TITLE,Build.DISPLAY);
  ((SystemUpdateManager)getSystemService(SYSTEM_UPDATE_SERVICE)).updateSystemUpdateInfo(b);
 }
 private void completeInstalled(){long pending=getSharedPreferences(PREF,0).getLong("pendingSequence",0);
  if(pending>0&&SystemProperties.getLong("ro.kiki.ota.sequence",0)>=pending&&SystemProperties.get("sys.kiki.ota.boot_verified").equals("1")){getSharedPreferences(PREF,0).edit().putLong("acceptedSequence",pending).commit();clearPending();state("更新已完成。当前系统："+Build.DISPLAY,SystemUpdateManager.STATUS_IDLE);}}
 public void onCreate(){super.onCreate();completeInstalled();
  if(SystemProperties.getBoolean("ro.boot.kiki_ota_rollback",false)){engine.resetStatus();clearPending();state("新槽未通过启动检查，已回退到原系统。用户数据未格式化；请查看日志。",SystemUpdateManager.STATUS_IDLE);}
  NotificationManager n=getSystemService(NotificationManager.class);n.createNotificationChannel(new NotificationChannel("ota","系统更新",NotificationManager.IMPORTANCE_LOW));
  startForeground(3,new Notification.Builder(this,"ota").setSmallIcon(android.R.drawable.stat_sys_download).setContentTitle("Kiki 系统更新").setContentText("签名全量 OTA · 保留用户数据").build());
  engine.bind(new UpdateEngineCallback(){
   public void onStatusUpdate(int s,float p){
    if(s==UpdateEngine.UpdateStatusConstants.UPDATED_NEED_REBOOT){installing=false;getSharedPreferences(PREF,0).edit().putBoolean("rebootReady",true).commit();state("更新已安装到备用槽。请重启完成更新。",SystemUpdateManager.STATUS_WAITING_REBOOT);}
    else if(s==UpdateEngine.UpdateStatusConstants.DOWNLOADING||s==UpdateEngine.UpdateStatusConstants.VERIFYING||s==UpdateEngine.UpdateStatusConstants.FINALIZING){installing=true;state("原生更新引擎：阶段 "+s+"，"+Math.round(p*100)+"%",SystemUpdateManager.STATUS_IN_PROGRESS);}
   }
   public void onPayloadApplicationComplete(int code){if(code!=0){installing=false;clearPending();state("安装失败（update_engine="+code+"）。当前系统保持有效；请查看日志后重试。",SystemUpdateManager.STATUS_IDLE);}}
  },new Handler(getMainLooper()));
 }
 public int onStartCommand(Intent i,int flags,int id){if(i==null)return START_NOT_STICKY;final String cmd=i.getStringExtra("command"),path=i.getStringExtra("path");
  worker.execute(()->{try{
   if(cmd.equals("resume")){for(int wait=0;wait<60&&!SystemProperties.get("sys.kiki.ota.boot_verified").equals("1");wait++)Thread.sleep(1000);completeInstalled();long pending=getSharedPreferences(PREF,0).getLong("pendingSequence",0);if(pending>current()&&!getSharedPreferences(PREF,0).getBoolean("rebootReady",false)){File f=new File(getSharedPreferences(PREF,0).getString("stage","/invalid"));if(!f.getCanonicalFile().getParentFile().getParentFile().equals(getFilesDir().getCanonicalFile()))throw new IOException("持久事务路径无效");apply(f,null);}}
   else if(cmd.equals("check")){if(installing||getSharedPreferences(PREF,0).getBoolean("rebootReady",false))throw new IOException("正在安装或等待重启，不能重复提交");check();}
   else if(cmd.equals("install")){if(candidate==null)throw new IOException("请先检查更新");download(candidate);}
   else if(cmd.equals("apply")){applyOffline(path);}
   else if(cmd.equals("reboot")){reboot();}
   else throw new IOException("未知命令");
  }catch(Exception e){android.util.Log.e("KikiUpdater","OTA command failed",e);if(!installing&&!getSharedPreferences(PREF,0).getBoolean("rebootReady",false)){discardStage(stageFile);clearPending();state("更新未完成："+e.getMessage(),SystemUpdateManager.STATUS_IDLE);}}});return START_NOT_STICKY;
 }
 public IBinder onBind(Intent i){return null;}
 public void onDestroy(){engine.unbind();worker.shutdown();super.onDestroy();}
 private PublicKey key()throws Exception{try(InputStream in=getResources().openRawResource(com.kiki.updater.R.raw.ota_public)){return KeyFactory.getInstance("RSA").generatePublic(new X509EncodedKeySpec(bounded(in,4096)));}}
 private JSONObject authenticate(byte[] raw,byte[] sig)throws Exception{
  if(raw.length>65536||sig.length!=256)throw new IOException("签名元数据长度错误");Signature v=Signature.getInstance("SHA256withRSA");v.initVerify(key());v.update(raw);if(!v.verify(sig))throw new IOException("不是受信任的 Kiki OTA 签名");
  // JSONObject normally accepts duplicate keys; reject them before interpreting security metadata.
  String text=new String(raw,java.nio.charset.StandardCharsets.UTF_8);Set<String> keys=new HashSet<>();java.util.regex.Matcher m=java.util.regex.Pattern.compile("\\\"([^\\\"\\\\]+)\\\"\\s*:").matcher(text);while(m.find())if(!keys.add(m.group(1)))throw new IOException("重复的 OTA 字段");
  JSONObject j=new JSONObject(text);Set<String> allowed=new HashSet<>(Arrays.asList("kind","format","device","layout","android_major","sequence","version","payload_sha256","payload_bytes","ota_url"));
  Iterator<String> it=j.keys();while(it.hasNext())if(!allowed.remove(it.next()))throw new IOException("未知 OTA 字段");if(!allowed.isEmpty())throw new IOException("OTA 字段缺失");
  if(!j.getString("kind").equals("org.kiki.ota.full")||j.getInt("format")!=1||!j.getString("device").equals("kikiaosp_test")||!j.getString("layout").equals("gpt-ab-v1")||j.getInt("android_major")!=17)throw new IOException("设备/布局不兼容");
  if(!j.getString("payload_sha256").matches("[0-9a-f]{64}")||j.getLong("payload_bytes")<=0||j.getLong("payload_bytes")>MAX||j.getLong("sequence")<=0)throw new IOException("无效的 OTA 完整性约束");
  return j;
 }
 private long current(){return Math.max(SystemProperties.getLong("ro.kiki.ota.sequence",1),getSharedPreferences(PREF,0).getLong("acceptedSequence",0));}
 private void check()throws Exception{
  state("正在检查 GitHub 官方 Release…",SystemUpdateManager.STATUS_IDLE);JSONArray releases=new JSONArray(new String(fetch(API,1024*1024),"UTF-8"));JSONObject best=null;int rejected=0;
  for(int r=0;r<releases.length();r++){JSONObject release=releases.getJSONObject(r);if(release.optBoolean("draft"))continue;JSONArray assets=release.getJSONArray("assets");String meta=null,sig=null;
   for(int a=0;a<assets.length();a++){JSONObject asset=assets.getJSONObject(a);if(asset.getString("name").equals("KikiAOSP-ota.json"))meta=asset.getString("browser_download_url");if(asset.getString("name").equals("KikiAOSP-ota.sig"))sig=asset.getString("browser_download_url");}
   if(meta==null||sig==null)continue;
   try{JSONObject j=authenticate(fetch(meta,65536),fetch(sig,256));releaseUrl(j.getString("ota_url"));if(j.getLong("sequence")>current()&&(best==null||j.getLong("sequence")>best.getLong("sequence")))best=j;}catch(Exception e){rejected++;android.util.Log.w("KikiUpdater","Rejected release metadata",e);}
  }
  candidate=best;if(best!=null)state("发现更新："+best.getString("version")+"\n点击下载并安装；不会清除用户数据。",SystemUpdateManager.STATUS_WAITING_DOWNLOAD);
  else if(rejected>0)throw new IOException("发现无法验证的发布信息，不能声称已是最新版本");
  else state("当前已是最新的兼容版本。\n当前序列："+current()+"（没有更新的已签名 OTA）",SystemUpdateManager.STATUS_IDLE);
 }
 private static void releaseUrl(String s)throws Exception{URI u=new URI(s);if(!u.getScheme().equals("https")||!u.getHost().equals("github.com")||!u.getPath().startsWith("/kekeqwq/kikiaosp_test/releases/download/")||u.getUserInfo()!=null||u.getFragment()!=null||u.getPort()!=-1)throw new IOException("不允许的 OTA 发布地址");}
 private HttpsURLConnection connection(String address)throws Exception{
  for(int redirects=0;redirects<6;redirects++){URL u=new URL(address);String h=u.getHost();if(!u.getProtocol().equals("https")||!(h.equals("api.github.com")||h.equals("github.com")||h.endsWith(".githubusercontent.com"))||u.getUserInfo()!=null)throw new IOException("更新地址不是受允许的 HTTPS GitHub 地址");
   HttpsURLConnection c=(HttpsURLConnection)u.openConnection();c.setConnectTimeout(15000);c.setReadTimeout(30000);c.setInstanceFollowRedirects(false);c.setRequestProperty("User-Agent","KikiUpdater/0.3");c.setRequestProperty("Accept","application/vnd.github+json");int code=c.getResponseCode();
   if(code>=300&&code<400){String loc=c.getHeaderField("Location");c.disconnect();if(loc==null)throw new IOException("无效的下载重定向");address=new URL(u,loc).toString();continue;}
   if(code!=200){c.disconnect();throw new IOException("GitHub HTTP "+code);}return c;
  }throw new IOException("重定向次数超限");
 }
 private byte[] fetch(String url,int limit)throws Exception{HttpsURLConnection c=connection(url);try(InputStream in=c.getInputStream()){return bounded(in,limit);}finally{c.disconnect();}}
 private static byte[] bounded(InputStream in,int limit)throws Exception{ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] b=new byte[8192];for(int n;(n=in.read(b))!=-1;){if(out.size()+n>limit)throw new IOException("元数据超出上限");out.write(b,0,n);}return out.toByteArray();}
 private File newStage()throws Exception{File d=new File(getFilesDir(),"ota-"+UUID.randomUUID());if(!d.mkdir())throw new IOException("无法创建独立更新目录");stageFile=new File(d,"update.ota.zip");return stageFile;}
 private void download(JSONObject j)throws Exception{
  if(installing||getSharedPreferences(PREF,0).getBoolean("rebootReady",false))throw new IOException("已有安装/待重启事务");File f=newStage();releaseUrl(j.getString("ota_url"));HttpsURLConnection c=connection(j.getString("ota_url"));long total=0;
  try(InputStream in=c.getInputStream();FileOutputStream out=new FileOutputStream(f)){byte[] b=new byte[65536];for(int n;(n=in.read(b))!=-1;){total+=n;if(total>MAX)throw new IOException("更新包超出上限");out.write(b,0,n);if(total%(16*1024*1024)<65536)state("下载中："+(total/(1024*1024))+" MiB",SystemUpdateManager.STATUS_WAITING_DOWNLOAD);}out.getFD().sync();}finally{c.disconnect();}
  apply(f,j);
 }
 private void applyOffline(String path)throws Exception{
  if(path==null||!path.matches("/data/local/tmp/kiki-ota/incoming-[0-9a-f-]{36}\\.ota\\.zip"))throw new IOException("非实例专属 OTA 暂存路径");if(installing||getSharedPreferences(PREF,0).getBoolean("rebootReady",false))throw new IOException("已有安装/待重启事务");
  File src=new File(path);if(!src.getCanonicalPath().equals(path)||src.length()<=0||src.length()>MAX)throw new IOException("无效的离线包");File f=newStage();
  try(FileInputStream in=new FileInputStream(src);FileOutputStream out=new FileOutputStream(f)){byte[] b=new byte[65536];long size=0;for(int n;(n=in.read(b))!=-1;){size+=n;if(size>MAX)throw new IOException("包超出上限");out.write(b,0,n);}out.getFD().sync();}
  SystemProperties.set("sys.kiki.ota.imported",path.substring(path.lastIndexOf("incoming-")+9,path.length()-8));
  apply(f,null);
 }
 private void apply(File file,JSONObject expected)throws Exception{
  state("正在校验签名和完整 payload…",SystemUpdateManager.STATUS_WAITING_INSTALL);
  try(ZipFile zip=new ZipFile(file)){
   Set<String> names=new HashSet<>();Enumeration<? extends ZipEntry> entries=zip.entries();while(entries.hasMoreElements()){String name=entries.nextElement().getName();if(!names.add(name)||!(name.equals("payload.bin")||name.equals("payload_properties.txt")||name.equals("kiki-ota.json")||name.equals("kiki-ota.sig")||name.equals("META-INF/com/android/metadata")))throw new IOException("重复/非法 ZIP 条目");}
   if(names.size()!=5)throw new IOException("不完整的全量 OTA");JSONObject j=authenticate(bounded(zip.getInputStream(zip.getEntry("kiki-ota.json")),65536),bounded(zip.getInputStream(zip.getEntry("kiki-ota.sig")),256));
   if(expected!=null&&!expected.toString().equals(j.toString()))throw new IOException("下载包与已验证发布信息不一致");if(j.getLong("sequence")<=current())throw new IOException("拒绝重复更新/降级");
   ZipEntry payload=zip.getEntry("payload.bin");if(payload.getMethod()!=ZipEntry.STORED||payload.getSize()!=j.getLong("payload_bytes"))throw new IOException("payload 必须未压缩且长度匹配");
   MessageDigest hash=MessageDigest.getInstance("SHA-256");long read=0;try(InputStream in=zip.getInputStream(payload)){byte[] b=new byte[65536];for(int n;(n=in.read(b))!=-1;){read+=n;if(read>j.getLong("payload_bytes"))throw new IOException("payload 长度超限");hash.update(b,0,n);}}
   if(read!=j.getLong("payload_bytes")||!hex(hash.digest()).equals(j.getString("payload_sha256")))throw new IOException("payload SHA256 不匹配");
   String properties=new String(bounded(zip.getInputStream(zip.getEntry("payload_properties.txt")),8192),"UTF-8");List<String> headers=new ArrayList<>();Set<String> props=new HashSet<>();for(String line:properties.split("\n")){if(line.isEmpty())continue;String[] pair=line.split("=",2);if(pair.length!=2||!props.add(pair[0])||!Arrays.asList("FILE_HASH","FILE_SIZE","METADATA_HASH","METADATA_SIZE").contains(pair[0]))throw new IOException("无效 payload 属性");headers.add(line);}
   if(props.size()!=4||!properties.contains("FILE_HASH="+Base64.encodeToString(hashOf(file,zip,payload),Base64.NO_WRAP)))throw new IOException("payload 属性/hash 不一致");
   long offset=payloadOffset(file,payload.getSize());getSharedPreferences(PREF,0).edit().putLong("pendingSequence",j.getLong("sequence")).putString("stage",file.getAbsolutePath()).commit();
   headers.add("SWITCH_SLOT_ON_REBOOT=1");headers.add("RUN_POST_INSTALL=0");installing=true;engine.applyPayload("file://"+file.getAbsolutePath(),offset,payload.getSize(),headers.toArray(new String[0]));
  }
 }
 private byte[] hashOf(File f,ZipFile z,ZipEntry e)throws Exception{MessageDigest d=MessageDigest.getInstance("SHA-256");try(InputStream in=z.getInputStream(e)){byte[] b=new byte[65536];for(int n;(n=in.read(b))!=-1;)d.update(b,0,n);}return d.digest();}
 private long payloadOffset(File f,long size)throws Exception{try(RandomAccessFile in=new RandomAccessFile(f,"r")){long p=0;while(p+30<in.length()){in.seek(p);byte[] h=new byte[30];in.readFully(h);if(le(h,0,4)!=0x04034b50L)break;long bytes=le(h,18,4);int nl=(int)le(h,26,2),el=(int)le(h,28,2);if(nl>128||el>4096||(le(h,6,2)&9)!=0)throw new IOException("不支持的 ZIP 标志/长度");byte[] name=new byte[nl];in.readFully(name);long start=p+30+nl+el;if(new String(name,"UTF-8").equals("payload.bin")){if(bytes!=size||le(h,8,2)!=0||start+size>in.length())throw new IOException("payload offset/size 错误");return start;}p=start+bytes;}throw new IOException("找不到原始 payload offset");}}
 private static long le(byte[] b,int p,int n){long v=0;for(int i=0;i<n;i++)v|=(long)(b[p+i]&255)<<(i*8);return v;}
 private static String hex(byte[] b){StringBuilder s=new StringBuilder();for(byte x:b)s.append(String.format(java.util.Locale.ROOT,"%02x",x&255));return s.toString();}
 private void reboot()throws Exception{if(!getSharedPreferences(PREF,0).getBoolean("rebootReady",false))throw new IOException("没有已完成的待重启更新");
  // Host owns the virtual bootloader. A plain QEMU RESET reloads the old -kernel.
  SystemProperties.set("sys.kiki.ota.reboot","1");state("正在正常关机并切换系统槽…",SystemUpdateManager.STATUS_WAITING_REBOOT);
 }
}
