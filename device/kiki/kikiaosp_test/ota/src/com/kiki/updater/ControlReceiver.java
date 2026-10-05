// SPDX-License-Identifier: Apache-2.0
package com.kiki.updater;
import android.content.*;
public final class ControlReceiver extends BroadcastReceiver {
 public void onReceive(Context c,Intent i){String cmd=i.getStringExtra("command");
  if(Intent.ACTION_BOOT_COMPLETED.equals(i.getAction())){c.startForegroundService(new Intent(c,UpdateService.class).putExtra("command","resume"));return;}
  if(cmd==null||cmd.equals("status")){setResultData(UpdateService.status(c));return;}
  if(!cmd.equals("check")&&!cmd.equals("apply")&&!cmd.equals("reboot")){setResultCode(1);setResultData("Invalid update command");return;}
  Intent service=new Intent(c,UpdateService.class).putExtra("command",cmd);
  if(cmd.equals("apply"))service.putExtra("path",i.getStringExtra("path"));
  c.startForegroundService(service);setResultData("Accepted: "+cmd);
 }
}
