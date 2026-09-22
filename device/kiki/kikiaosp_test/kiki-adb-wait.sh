#!/system/bin/sh
while [ ! -x /system/bin/kiki-adbd ]; do
    sleep 1
done
while [ ! -f /system/etc/aconfig/package.map ]; do
    sleep 1
done
mkdir -p /metadata/aconfig/maps /metadata/aconfig/boot || exit 1
cp /system/etc/aconfig/package.map /metadata/aconfig/maps/com.android.adbd.package.map || exit 1
cp /system/etc/aconfig/flag.val /metadata/aconfig/boot/com.android.adbd.val || exit 1
setprop sys.kiki.aconfig.ready 1
