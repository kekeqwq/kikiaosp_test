#!/system/bin/sh
while [ ! -x /system/bin/adbd ]; do
    sleep 1
done

# Bring up the QEMU Ethernet link early for TCP ADB. KikiConnectivityOverlay
# gives Android EthernetService the same static address, gateway and DNS;
# it will later register the app-visible default network.
for n in 1 2 3 4 5 6 7 8 9 10; do
    /system/bin/ifconfig eth0 10.0.2.15 netmask 255.255.255.0 up >/dev/kmsg 2>&1 && break
    sleep 1
done
if ! ip rule show | grep -q '^100:.*to 10.0.2.0/24 lookup main'; then
    ip rule add pref 100 to 10.0.2.0/24 lookup main >/dev/kmsg 2>&1
fi

# Android userdebug may start the stock USB daemon first. This product uses
# the Kiki TCP daemon, which starts after the network route is ready.
stop adbd
setprop sys.kiki.aconfig.ready 1

# Mark the test user ready and make Launcher3 Quickstep the default HOME.
sleep 50
# A reused userdata image may carry an older media volume. Set the real
# AudioService stream, rather than only changing SettingsProvider storage.
for n in 1 2 3 4 5; do
    /system/bin/cmd media_session volume --stream 3 --set 15 >/dev/kmsg 2>&1 && break
    sleep 2
done
# Batteryless QEMU reports UNKNOWN battery status, which Android treats as
# externally powered. The stock stay-awake policy keeps this test display on
# while the launcher or Settings is in the foreground.
/system/bin/settings put global stay_on_while_plugged_in 15 >/dev/kmsg 2>&1
/system/bin/settings put global device_provisioned 1 >/dev/kmsg 2>&1
/system/bin/settings --user 0 put secure user_setup_complete 1 >/dev/kmsg 2>&1
/system/bin/cmd package set-home-activity --user 0 com.android.launcher3 >/dev/kmsg 2>&1
