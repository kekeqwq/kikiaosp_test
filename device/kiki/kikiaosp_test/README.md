# KikiAOSP test device tree

This is the device-owned Android 17 ARM64 configuration for upstream QEMU's
`virt` machine and Ranchu/Goldfish display stack. Its identities are
`kikiaosp_test` and `KikiAOSP`; the legacy lunch/product target remains
`kikiaosp_test_arm64_phone` for output-path compatibility, but the product is
not a phone and has no telephony hardware.

## Product profile

The product composes AOSP `core_64_bit.mk` and `core_minimal.mk`, then adds the
user-facing APKs needed for normal use: `Launcher3QuickStep`, `Settings`,
`Gallery2`, `WallpaperPicker2`, `SystemUI`, and `LatinIME`. AOSP's existing
`MediaProvider` supplies the system Photo Picker. `KikiWindowTest` remains a
source-level regression fixture and is not installed. The product does not inherit the broad
`aosp_arm64.mk` GSI product, nor does it apply a large after-the-fact package
removal list. The product selects the full Framework startup branch and keeps
AOSP's core system/APEX packages. Features that have no device endpoint (radio
and battery) are explicitly gated. Some Kiki-specific Framework conditionals
remain in the tracked AOSP patch set and still require a boot audit; this
product definition alone does not claim those services have all started.

The current Surface defaults are a 288 dpi Android display density, font scale
1.5, Asia/Shanghai time zone, and a 1003×1556 native guest display. Keyboard
repeat is initialized to a 2000 ms initial hold and 1000 ms repeat interval,
but only when the user has not already chosen values. The `sys.use_memfd`
compatibility property is enabled because the 202604 vendor API no longer has
`/dev/ashmem`, while the tested Maimemo APK targets SDK 36.

`kiki-minimal-native.rc` is a historical filename retained for the current
image-repacker interface. It now contains only the standard Android process
environment exports. It must never stop `audioserver`, `netd`, graphics,
storage, KeyMint, or other native services.

## Device integration

- `BoardConfig.mk`: ARM64-only userspace, EROFS system/vendor images, and
  upstream Ranchu SELinux policy, plus real product/system_ext images for the
  Gallery2 and WallpaperPicker2 app partitions.
- `fstab.ranchu` and `init.ranchu.rc`: first/second-stage partition mounting
  for the virtio block devices, including late `/data`.
- `kiki_hwc3.xml` and the product HWC packages: AIDL composer3, minigbm
  allocator/mapper, and Pastel Vulkan for native SurfaceFlinger composition.
- `kiki-adb.rc`: test-only TCP ADB control path used by the verified local
  QEMU workflow.
- `kiki-user-defaults.rc` and `kiki-user-defaults.sh`: one-time-at-boot,
  unset-only initialization for physical keyboard repeat settings.
- `overlay/`: fixed-display resources for a virtual device without an
  orientation sensor.
- `apps/KikiWindowTest/`: the normal APK target with a visible Close button
  and a two-color animation, retained only as a buildable UI regression
  fixture; it is intentionally not installed in the normal product.

## Temporary runtime compatibility data

`prebuilt/framework/` aliases are still referenced by the current tracked AOSP
ART/app_process integration patch. They are deliberately isolated in the
product makefile and are technical debt, not the target runtime design. Remove
them only in the same change that restores Android 17's generated APEX
bootclasspath and passes the complete boot/UI validation. Do not copy a static
`ld.config` over Android's generated APEX-aware linker configuration.

## Sync and build

From `kikiaosp_test`, synchronize into an Android 17 AOSP checkout with:

```sh
scripts/sync-device-tree.sh ~/aosp-master
```

The sync overlays this device-tree directory and intentionally preserves
unknown destination files; use a clean AOSP checkout for a reproducible
baseline. Then build `kikiaosp_test_arm64_phone-cp2a-userdebug` using
the repository's main README. Do not modify upstream source outside the
tracked patch/overlay integration.
