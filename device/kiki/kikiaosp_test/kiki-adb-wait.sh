#!/system/bin/sh
while [ ! -x /system/apex/com.android.adbd/bin/adbd ]; do
    sleep 1
done
setprop service.adb.tcp.port 5555
exec /system/apex/com.android.adbd/bin/adbd --root_seclabel=u:r:su:s0
