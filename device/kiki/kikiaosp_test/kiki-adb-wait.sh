#!/system/bin/sh
while [ ! -x /system/bin/kiki-adbd ]; do
    sleep 1
done
setprop service.adb.tcp.port 5555
exec /system/bin/kiki-adbd --root_seclabel=u:r:su:s0
