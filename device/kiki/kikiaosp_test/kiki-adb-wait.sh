#!/system/bin/sh
while [ ! -x /system/bin/adbd ]; do
    sleep 1
done

# This minimal QEMU product has no DHCP-managed Android default network.
# Assign the address used by QEMU user networking, then make its directly
# connected subnet visible before Android's policy-routing unreachable rule.
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

# Select the small Kiki Home as the default launcher before the test Activity
# starts. Closing that window must return to an Activity that draws promptly.
sleep 50
# Batteryless QEMU reports UNKNOWN battery status, which Android treats as
# externally powered. The stock stay-awake policy keeps this test display on
# even after the test Activity's FLAG_KEEP_SCREEN_ON window is closed.
/system/bin/settings put global stay_on_while_plugged_in 15 >/dev/kmsg 2>&1
/system/bin/settings put global device_provisioned 1 >/dev/kmsg 2>&1
/system/bin/settings --user 0 put secure user_setup_complete 1 >/dev/kmsg 2>&1
/system/bin/cmd package set-home-activity --user 0 com.kikiaosp.windowtest >/dev/kmsg 2>&1
/system/bin/am start --user 0 -n com.kikiaosp.windowtest/.MainActivity >/dev/kmsg 2>&1
