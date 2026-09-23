#!/system/bin/sh
while [ ! -x /system/bin/adbd ]; do
    sleep 1
done
# The minimal product intentionally has no netd/DHCP stack. Configure the
# virtio-net interface for QEMU's user-mode network before exposing ADB.
for n in 1 2 3 4 5 6 7 8 9 10; do
    /system/bin/ifconfig eth0 10.0.2.15 netmask 255.255.255.0 up >/dev/kmsg 2>&1 && break
    sleep 1
done
# The stable black-screen image intentionally has no metadata partition.
# adbd is built with the unlocked test-target auth bypass, so no aconfig
# persistence is needed for this bring-up transport.
setprop sys.kiki.aconfig.ready 1
