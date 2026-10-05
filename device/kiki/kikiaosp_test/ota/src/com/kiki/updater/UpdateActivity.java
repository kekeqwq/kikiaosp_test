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
  TextView title=new TextView(this);title.setText("Kiki System Update");title.setTextSize(28);root.addView(title);
  TextView intro=new TextView(this);intro.setText("Full system updates, keeping your apps and data.\nChecks official GitHub Releases automatically; no source version to select.\nBack up important data before updating.");root.addView(intro);
  state=new TextView(this);state.setTextSize(17);root.addView(state,new LinearLayout.LayoutParams(-1,0,1));
  button(root,"Check for updates","check");button(root,"Download and install","install");button(root,"Restart to finish","reboot");
 }
 private void button(LinearLayout root,String label,String command){Button b=new Button(this);b.setText(label);root.addView(b);b.setOnClickListener(v->{
  if(command.equals("reboot")){new android.app.AlertDialog.Builder(this).setTitle("Restart to finish updating?").setMessage("Android will shut down safely. KikiEmu will then start the updated system slot. Keep your PC powered on.").setPositiveButton("Restart",(d,w)->send(command)).setNegativeButton("Cancel",null).show();}
  else if(command.equals("install")){new android.app.AlertDialog.Builder(this).setTitle("Install the verified update?").setMessage("The update installs to the inactive slot without erasing your data. You can choose when to restart after installation.").setPositiveButton("Install",(d,w)->send(command)).setNegativeButton("Cancel",null).show();}
  else send(command);
 });}
 private void send(String command){startForegroundService(new Intent(this,UpdateService.class).putExtra("command",command));}
 protected void onResume(){super.onResume();timer.post(refresh);}
 protected void onPause(){timer.removeCallbacks(refresh);super.onPause();}
}
