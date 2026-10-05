// SPDX-License-Identifier: Apache-2.0
package com.kiki.updater;
import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.content.Intent;
import android.widget.*;

public final class UpdateActivity extends Activity {
 private TextView state; private final Handler timer=new Handler();
 private final Runnable refresh=new Runnable(){public void run(){state.setText(UpdateService.status(UpdateActivity.this));timer.postDelayed(this,1000);}};
 public void onCreate(Bundle b){super.onCreate(b);LinearLayout root=new LinearLayout(this);root.setOrientation(1);root.setPadding(32,40,32,32);setContentView(root);
  TextView title=new TextView(this);title.setText("Kiki 系统更新");title.setTextSize(28);root.addView(title);
  TextView intro=new TextView(this);intro.setText("全量系统更新 · 保留应用和数据\n自动检查官方 GitHub Release；不需要选择源版本。\n升级前建议备份重要数据。");root.addView(intro);
  state=new TextView(this);state.setTextSize(17);root.addView(state,new LinearLayout.LayoutParams(-1,0,1));
  button(root,"检查更新","check");button(root,"下载并安装更新","install");button(root,"重启完成更新","reboot");
 }
 private void button(LinearLayout root,String label,String command){Button b=new Button(this);b.setText(label);root.addView(b);b.setOnClickListener(v->{
  if(command.equals("reboot")){new android.app.AlertDialog.Builder(this).setTitle("重启完成更新？").setMessage("Android 将正常关机，KikiEmu 自动从新系统槽启动。请勿关闭电脑。").setPositiveButton("重启",(d,w)->send(command)).setNegativeButton("取消",null).show();}
  else if(command.equals("install")){new android.app.AlertDialog.Builder(this).setTitle("安装已验证的更新？").setMessage("系统将写入备用槽，不清除用户数据；完成后由你决定重启。").setPositiveButton("安装",(d,w)->send(command)).setNegativeButton("取消",null).show();}
  else send(command);
 });}
 private void send(String command){startForegroundService(new Intent(this,UpdateService.class).putExtra("command",command));}
 protected void onResume(){super.onResume();timer.post(refresh);}
 protected void onPause(){timer.removeCallbacks(refresh);super.onPause();}
}
