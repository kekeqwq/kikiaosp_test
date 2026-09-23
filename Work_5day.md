# Work 5 — reproducible baseline and ADB bring-up

Date: 2026-09-23

## Baseline audit

- Device repository: `kikiaosp_test` (`67afeba`)
- Product: `kikiaosp_test_arm64_phone`
- Build variant: `trunk_staging userdebug`
- AOSP integration: 146 tracked paths exactly match `patches/aosp-working-tree.patch`; 5 untracked paths exactly match `overlays/`.
- Audit command: `scripts/audit-aosp-integration.sh /home/keke/aosp-master`
- No unrelated AOSP changes were found.

The audit is now a required pre-build gate. The README no longer uses the `eng` lunch target, and the incremental command is `m -j$(nproc) systemimage`; this prevents an accidental variant switch and installclean.

## Incremental build

The TCP-only adbd init change (`67afeba`) rebuilt successfully on 185 in 5 Ninja steps (~30 seconds). It reused the existing Soong graph and did not run a full compile.

## Local QEMU result

The rc4 kernel and rebuilt system image booted to the established stable black-screen baseline. SurfaceFlinger still reaches the known graphics checkpoint. The adbd service starts, but the host sees `127.0.0.1:5555` as `offline`; no `adbd started` line appears after authentication initialization. QEMU was stopped after the test.

Next controlled step: instrument or bypass the adbd authentication initialization path while preserving the TCP-only transport. Do not touch unrelated AOSP projects; every change must enter this repository's patch/overlay set and pass the audit before rebuilding.

## Final ADB checkpoint

The no-auth transport path is now proven on the rc4 image. The guest configures
`eth0` as `10.0.2.15/24` for QEMU user networking, adbd listens on `tcp:5555`,
and the host connects successfully:

```text
127.0.0.1:5555 device product:kikiaosp_test_arm64_phone model:KikiAOSP_ARM64_Phone device:kikiaosp_test
uid=2000(shell) gid=2000(shell)
ro.product.device=kikiaosp_test
ro.product.name=kikiaosp_test_arm64_phone
```

The stable black-screen boot remains intact. The QEMU process was stopped after
the regression test. All functional changes are committed in this repository;
the corresponding kernel remains the rc4 artifact from `kikiaosp_kernel`.

A subsequent approximately two-minute run kept the ADB transport in `device`
state and produced no kernel panic or kernel BUG; QEMU was then terminated.
SurfaceFlinger still reports the previously known EGL/HWC abort loop, so this
checkpoint claims a stable kernel/ADB transport and black output, not a visible
desktop or a completed scanout path.

### 2026-09-23 stable display + ADB checkpoint

The previous stable display composition was restored and tested with the rc4 kernel:

- Reused the known-good `kiki-kernel-ramdisk.img` and `kiki-kernel-system.img` composition.
- Kept `kernel-linux-7.3-rc4-4k`; serial output reaches `WINQ-SF primary connected=1` and `WINQ-SF: after flinger init` without SurfaceFlinger EGL aborts.
- Injected the reproducible patched `kiki-adbd`, `kiki-adb.rc`, and the virtio-network setup script into a repacked EROFS system image.
- The stable image has no metadata partition, so the ADB staging script no longer requires aconfig persistence; the unlocked test-target adbd starts directly after configuring `eth0`.
- Local QEMU test stayed alive for more than 30 seconds, `adb connect 127.0.0.1:5555` reports `device`, and `adb shell id` succeeds.

This is the first combined checkpoint with both a stable black display path and ADB online. The QEMU process was stopped after validation; the repack is reproducible from the stable image tree plus the tracked ADB payload.
