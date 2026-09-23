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

### 2026-09-23 correction: active scanout and device identity

The previous checkpoint overstated the display result. The user still saw
QEMU's `Display output is not active`; `WINQ-SF primary connected=1` only
proved that SurfaceFlinger discovered a display. The frozen product has no UI
layer and its HWC did not submit a first frame. ADB also reported the old
`vsoc_arm64` identity from the frozen image, and the host did not retain a TCP
device across every QEMU restart.

Added `device/kiki/kikiaosp_test/kiki_black_scanout.c` and its init service.
It is a static ARM64 Linux DRM/KMS helper, triggered after HWC announces
`sys.kiki.hwc.ready=1`. It creates a zeroed dumb buffer, sets the connector's
CRTC once, drops DRM master, and holds the framebuffer alive. It has no libc
or Android graphics library dependency. The first attempt failed while
fetching DRM resource IDs; after supplying all ioctl output arrays, serial
reported `KIKI-BLACK scanout active` on each cold boot.

The tested QEMU window was captured directly through the Windows window API:
its display area is pure black and contains no `Display output is not active`
text. The QEMU monitor also exported a black frame. The final deterministic
repack was cold booted again and showed the same actual window result.
`adb devices -l` reported `device ... device:kikiaosp_test`, `adb shell id`
succeeded, and `ro.product.device` returned `kikiaosp_test`. The kernel remains
`7.3.0-rc4-4k`. The QEMU window was left open for the user's observation.

The tracked `scripts/repack-black-baseline.sh` takes the frozen EROFS base,
the matching AOSP `adbd_flags_c_lib.so`, and the repository's ADB and DRM
sources. It also fixes the old `vsoc_arm64` partition properties. Two clean
repack runs produced byte-identical EROFS images. Source base SHA-256:
`ad60b844b0a23c835aaf129f548b0fff03f1bf01588cb6645c9b3a0f0f6b20d7`.
Final image SHA-256:
`c0c7f7f3737052dd4f53f8d3892d0278aa4cb2f0f32ec12f07a3aebde2054cc7`.

The black frame is a minimum active scanout proof, not a SurfaceFlinger-owned
layer or a desktop. A future client-target frame can replace it through HWC.

The frozen base system and ramdisk are now published as the GitHub release
`black-baseline-2026-09-23`. GitHub reports both assets uploaded with matching
SHA-256 digests. This keeps the 491 MB binary out of Git history while making
the repository's repack script usable on a new development host. The final
QEMU process remained alive with ADB in `device` state during the release upload.

## 2026-09-23 — final Windows display-window check

The QEMU launcher was corrected to show the GTK display window while keeping
the auxiliary process console hidden. A fresh launch left exactly one visible
QEMU window. A captured window image showed a uniformly black frame, with no
`Display output is not active` overlay. This is the intended minimal active
scanout proof; it is not evidence of a rendered Android desktop or a
SurfaceFlinger-owned frame.

During this observation, `127.0.0.1:5555` remained in ADB `device` state. The
device reported `ro.product.device=kikiaosp_test`,
`init.svc.kiki_black_scanout=running`, and kernel `7.3.0-rc4-4k`; shell commands
including `id` and `uname -r` succeeded. The QEMU process was left running for
the user to inspect. No claim is made here about a half-hour soak test.
