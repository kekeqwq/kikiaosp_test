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

## 2026-09-23 — animated native DRM/KMS `TEST OK` proof

Added an optional `test-ui` variant to `scripts/build-black-scanout.sh` and
`scripts/repack-black-baseline.sh`, with `device/kiki/kikiaosp_test/kiki_test_scanout.rc`.
The tiny static ARM64 helper is launched by Android init after
`sys.kiki.hwc.ready=1`. It selects the 640x480 KMS mode, draws a white 5x7
`TEST OK` bitmap, then moves a colored square and alternates orange/green at
500 ms intervals. It uses no libc, Activity, launcher, SurfaceComposer client,
or additional Android framework services. The original black-baseline mode
remains the default and is not modified.

The first update attempt could draw only one frame: `DRM_IOCTL_MODE_DIRTYFB`
for the next frame failed after the helper released DRM master. In the
test-only variant it now retains DRM master while submitting full-frame dirty
updates. The AOSP base source was not edited; `scripts/audit-aosp-integration.sh`
reports a clean and reproducible integration after syncing the device-tree
overlay. Failed SurfaceComposer/Gralloc client experiments were removed from
the product definition; those experiments did not present a frame.

Reproduced and booted image SHA-256:
`1b09adb50bc909ed67af614e8726f8171dd5072c9b8cad49083f8d0abb0f6105`.
Two QEMU monitor captures show the same complete `TEST OK` text with the
animated square at different positions/colors. Their PPM SHA-256 values are
`215e3813a4ed46c09025a948f11a182df6d3e839dd45bc53dcb08b06482c2443` and
`ad92ae6d46616cf011db15a928800e7695170ed169304fe1b09d2ba81c46ce08`.
The guest log records `initial dirtyfb submitted` and
`second frame dirtyfb submitted`; ADB remains `device` and the guest kernel
remains `7.3.0-rc4-4k`.

This establishes Android init userspace -> DRM/KMS -> QEMU scanout and proves
at least two changing output frames. It does not establish a
SurfaceFlinger/HWC-presented Android UI: the test helper deliberately owns DRM
master, and the known HWC present path remains a separate follow-up. QEMU was
left running with the animated test image for live observation.

## 2026-09-23 — SurfaceFlinger native-layer handoff test

Added an optional `surface-test` repack path that uses the already-built
`kiki_test_ui`, the Ranchu composer APEX, and (for callback tracing) the
incrementally built SurfaceFlinger binary. The test client creates 53 color
layers plus a moving box and submits animated transactions every 500 ms. This
is a real SurfaceComposerClient workload, but successful transactions alone do
not prove scanout.

The Ranchu HWC APEX was built at its exact Soong output target, then activated
from `/vendor/apex/com.android.hardware.graphics.composer.ranchu.apex`. Runtime
logs confirm the AIDL composer service starts, opens DRM, detects the 640x480
display, and SurfaceFlinger calls its callback-registration chain; the AIDL
call reports success. However `dumpsys SurfaceFlinger --latency` still reports
only the 16,666,666 ns refresh period, layer history remains `active=0`, and
`FramebufferSurface frame-counter=0`. Thus no SurfaceFlinger frame reached the
display. The test image SHA-256 is
`d24ffff41364f60265dfe6a090025abdfdfe88314fdb6236d0bb78049539b8eb`.

This does not satisfy the SurfaceFlinger/HWC rendering goal and is not a
two-frame UI proof. The next investigation is the HWC callback transaction:
the client-side AIDL registration returns success, but the expected
server-side callback/VSYNC evidence is absent. Keep the direct-KMS animated
proof as a separate lower-layer milestone, not as a substitute for HWC
presentation. The test QEMU process was stopped after collecting the negative
frame-counter evidence.

## 2026-09-23 — HWC software-VSYNC synchronization test

The native layer test is alive: `kiki_test_ui` creates 53 text color layers plus
`KikiTestMovingBox`; serial output reports `TEST OK layers=54 animation=ready`
and transaction commits about every 0.52 seconds, while SurfaceFlinger dumpsys
shows the moving box at changing coordinates. This confirms transaction/layer
state updates, but not display presentation.

Found a C++ data race in the Ranchu software-VSYNC worker: `mVsyncEnabled` and
`mCallbacks` were written under `mStateMutex` but read without it. The worker
now snapshots both under the same lock before dispatching callbacks. AOSP
integration audit still passes (152 tracked patch paths, 5 overlays), and the
incremental HWC/APEX build succeeded in 19 seconds. Repacked test image SHA-256:
`53462e015080c1d178ad2be0a2b53ee8e6a584c776c695f7ff5811effed6836b`.

The test remains negative for real UI output: despite the synchronization fix,
`layerHistory={size=54, active=0}`, `FramebufferSurface frame-counter=0`, and
`dumpsys SurfaceFlinger --latency` shows only the 16,666,666 ns refresh period.
There is no logged `KikiAOSP software VSYNC callback active` event. So the data
race was real but not the sole blocker. Do not claim the requested animated UI
frames; the older direct-KMS two-frame capture remains a separate milestone.
Next trace should establish whether the AIDL `IComposerClient::registerCallback`
transaction actually reaches the active ComposerClient object, then follow the
first `onVsync` into SurfaceFlinger scheduling. This QEMU test was stopped after
confirming the zero-frame state.

## 2026-09-23 — first native SurfaceFlinger/HWC animation on screen

This supersedes the preceding negative SurfaceFlinger/HWC result: we now have
two distinct 640x480 QEMU monitor captures showing the Android test layers on
the actual display output. `kiki_test_ui` creates only two native solid-color
SurfaceComposer layers (background and moving square) and changes the square's
position/color every 500 ms. The guest remains ADB-accessible on the 7.3.0-rc4-4k
kernel.

Two integration details mattered. First, the frozen image starts the active
composer from `/system/bin/hwcomposer`; the initially repacked composer APEX
was present under `/vendor/apex` but was not mounted or used. Rebuilding and
installing the active non-APEX service made the `guest` composer choice take
effect. Second, minigbm's `GraphicBufferMapper::lock()` returns `-38` for the
composer output buffer. An opt-in GuestFrameComposer fallback now brackets a
dma-buf `mmap` with `DMA_BUF_IOCTL_SYNC`, writes the software composition, and
uses the existing DRM flush. The normal mapper-lock path remains first choice.

Build the active HWC binary on 185 in the `kiki-hwc-guest` tmux session:

```bash
source build/envsetup.sh
lunch kikiaosp_test_arm64_phone-trunk_staging-userdebug
m out/soong/.intermediates/device/generic/goldfish/hals/hwc3/android.hardware.graphics.composer3-service.ranchu/android_vendor_arm64_armv8-a/android.hardware.graphics.composer3-service.ranchu
```

After applying the repository patch set, the final tested system image was
repacked with:

```bash
scripts/repack-black-baseline.sh \
  /home/keke/kiki-kernel-system-black-adb.img \
  /home/keke/aosp-master \
  /home/keke/kiki-kernel-system-sf-guest-hwc3-map-ui.img surface-test
```

The image SHA-256 is
`cd87e319bf2322c41c8f0062b0ff2cc134d25873b3d08ad0f2199b3ab4be710f`.
QEMU ran with `androidboot.hardware.hwcomposer.mode=guest`, WHPX, 640x480
virtio-gpu, and upstream QEMU GTK display. The active guest
`/system/bin/hwcomposer` hash matched the built non-APEX service. Logcat shows
`KikiAOSP: mapped composition dma-buf` followed by continued test frame
commits.

QEMU monitor PPM evidence (PNG copies are in `docs/evidence/`):

- frame 1 SHA-256:
  `415cc6a70bfbb5f61f1cbf6b24e63ff0b811fe1b3dc32a109e200e589c275066`
- frame 2 SHA-256:
  `e45fa412a826659ecc707ca971003ec3bc35510dd0fd2ae5cfe330dbeeb537ee`

Both captures visibly show the dark background and square, with different
position/color. This proves the minimal real Android layer → SurfaceFlinger →
HWC → DRM/KMS → QEMU display path for solid-color layers. It does not yet
prove arbitrary app-buffer/client-target composition, launcher/input, sustained
stability, or high-refresh operation. The test QEMU window was deliberately
left open for live confirmation.

## Native animated `TEST OK` UI

Date: 2026-09-23

- Added readable `TEST OK` using a 5×7 glyph set rasterized as 53 horizontal
  solid-color SurfaceComposer effect layers, plus the existing dark background
  and moving square. The square's position and color update every 500 ms. No
  Launcher, application framework UI stack, or additional system service was
  introduced.
- Kept the experiment in the `surface-test` image mode, preserving the frozen
  black/ADB baseline. The tested image is
  `/home/keke/kiki-kernel-system-sf-guest-hwc3-map-ui-test-ok-v3.img`, SHA-256
  `bfe1c79716c623f684cb7376f9791c5df63ffa08545f0303fcb9c6e08d166f38`.
- Important build workflow finding: the project repository and AOSP checkout
  are separate directories. Editing only the project repo left
  `/home/keke/aosp-master/device/kiki/kikiaosp_test/kiki_test_ui.cpp` stale;
  `m kiki_test_ui` then reported success with zero actions and retained the old
  binary. After syncing the source, Ninja compiled the intended file and the
  resulting binary contained the `text-strokes` marker. Added
  `scripts/sync-device-tree.sh` and documented it in README to prevent another
  stale-copy build.
- The effective target rebuild after sync was 7 Ninja actions and about 19 s;
  this was not a full AOSP build. Image repack passed the EROFS check.
- Local Windows ARM QEMU used upstream QEMU + WHPX, 640×480 virtio-gpu, and
  guest HWC mode. At the last check the serial log recorded 1,210
  `frame committed ... status=0` transactions through 658 guest seconds;
  QEMU remained running and its stderr file was empty.
- Direct monitor captures are saved as
  `docs/evidence/kiki-native-test-ok-frame-1.png` and
  `docs/evidence/kiki-native-test-ok-frame-2.png`. Their PNG hashes are
  `78a9be76cd1655c1ea7dc116b920a6109cb9065276c908ac2ad93e36fcc33979` and
  `4aaaf0fde4d3e0db58ccd834adcae4d9823ab12a5ca4951c657ff459dfd98158`.
  The corresponding QEMU PPM hashes are
  `678406519929349d192b7e7fd9eaacf978f6b70640ccb2cbbf36bd4a63d99060` and
  `a4df9098b298373cf4c9f3f7202c1a1d62c15f51743586c3c30a8f5dbfeea128`.
- One early screenshot sample showed only the moving square. Four consecutive
  later screendumps showed the full text, background, and square at changing
  positions/colors. This meets the minimal two-frame proof, but a 30-minute
  stability run, high-refresh behavior, and ordinary app-buffer/client-target
  composition are still unverified.

## 2026-09-23 — ordinary GraphicBuffer prototype (initial build-pending checkpoint)

The next milestone is to replace only the moving square's synthetic
`SOLID_COLOR` effect layer with a normal buffer-backed SurfaceFlinger layer;
the readable text and dark background remain unchanged so the visual check is
easy. The EGL/BufferQueue experiment did not queue a buffer: ANGLE reported a
native-window/swapchain ownership conflict and SurfaceFlinger/HWC never listed
the EGL buffer as an active layer. The prototype therefore allocates two
ordinary `GraphicBuffer`s, writes two distinct opaque colors through their
dma-buf fds, and submits them directly with `Transaction::setBuffer` on a
normal `SurfaceControl`. Alternating the two immutable buffers should provide
the required two visibly different buffer frames without using EGL.

HWC already accepts `Composition::DEVICE`, but its source-buffer path had no
fallback when gralloc mapper locking failed (the composition target already
has a dma-buf mapping fallback). Added a separate AOSP integration patch that
keeps mapper lock as the primary path and falls back only for one-plane,
linear `ABGR8888`/`XBGR8888` buffers with an in-bounds crop. The fallback uses
read-only `mmap` bracketed by `DMA_BUF_IOCTL_SYNC`; unsupported layouts still
fail closed. The patch is isolated in
`patches/aosp-hwc-device-buffer-map.patch`, is applied after the existing HWC
output-buffer patch, and is included in the AOSP tracked-path audit. Dry-run,
patch application, device-tree sync, and the 155-path AOSP integration audit
all passed.

Important build status: no binary or image has been produced from this
prototype yet. AOSP Soong had to regenerate its large product graph after the
earlier temporary `Android.bp` header dependency was added and then removed.
The graph process reached about 31 GiB RSS on the 47 GiB host, leaving less
than 1 GiB available and reporting memory stalls. Three attempts were
deliberately interrupted before C++ compilation to avoid destabilizing the
build VM. The generated product Ninja manifest is currently incomplete and
reports unexpected EOF; it must be regenerated before the incremental HWC/UI
targets can run. Reducing `GOMEMLIMIT` and Go parallelism did not keep the
actual process RSS under the available-memory ceiling. The user chose to
continue with the current allocation and use swap for the reduced-speed build.
Rerun the two targets in the existing `kiki-hwc-guest` tmux session while
watching host responsiveness and remaining swap; a completed Soong graph
should then allow the incremental C++ actions to proceed.

The previously tested v3 `TEST OK` image is untouched and remains the visual
baseline. The current local Windows QEMU still runs that image. This prototype
has not been repacked, booted, or confirmed on screen; its source and patch
remain unvalidated until a successful build and QEMU test.

## 2026-09-24 — GraphicBuffer lifetime fix and Windows-host validation

The first GraphicBuffer image built and booted, but the hwcomposer crashed on
the first buffer-backed layer. The tombstone pointed to `ARGBBlendRow_NEON`
from `GuestFrameComposer::composeLayerInto`. The fallback's
`ScopedDmaBufMapping` had been scoped inside the `DEVICE` branch even though
`srcLayerSpec.buffer` was consumed later by blending; leaving the branch
unmapped the source before the blend. Moved the mapping owner to function
scope so its lifetime spans all composition operations. The fix is recorded
in `patches/aosp-hwc-device-buffer-map.patch`.

On VM185, the incremental rebuild of the composer took 3 Ninja actions and
about 15 seconds. The repacked image is
`/home/keke/kiki-kernel-system-sf-guest-hwc3-graphicbuffer-lifetimefix.img`
(SHA-256 `9313cedf3e35126d1a04d9264c3638b312792fb940bcb0ba909fcfc98568e8d7`).
It was tested on host 106, the local Windows ARM machine, using upstream QEMU
with WHPX, not on VM185.

Runtime checks on host 106: ADB connected to `kikiaosp_test`; SurfaceFlinger
and hwcomposer remained `running`, `sys.kiki.hwc.ready=1`, and the UI continued
to commit frames. The QEMU serial log reached frame 2277 (about 1,218 guest
seconds); there was no hwcomposer crash during this run. Ten direct QEMU
monitor PPM captures taken about 500 ms apart each contain the green text
pixels, with the square changing position/color. Two decoded PNG samples are
preserved at:

- `docs/evidence/graphicbuffer-lifetimefix-frame-02-verified.png` — SHA-256
  `86d7e6be829ee54af2b019880ce2ab635031b6f12f7d9c386ab8dfdedbd7b42e`;
  source PPM SHA-256 `cdaa6b68bb7f5b9a7e6af7ea9ef9140751893561aaea76b8de47c868e00f67cc`.
- `docs/evidence/graphicbuffer-lifetimefix-frame-07-verified.png` — SHA-256
  `78a9be76cd1655c1ea7dc116b920a6109cb9065276c908ac2ad93e36fcc33979`;
  source PPM SHA-256 `678406519929349d192b7e7fd9eaacf978f6b70640ccb2cbbf36bd4a63d99060`.

Evidence correction: earlier same-number PNG and PPM files were not a matched
conversion pair, which made some PNG previews look like text had disappeared.
For this validation, PNGs were regenerated from their PPM sources with FFmpeg
and the raw PPM text region was checked directly. Do not infer flicker from
the older mismatched pairs.

This proves the small native SurfaceFlinger `GraphicBuffer` layer can reach
the guest HWC and appear alongside the static test text over multiple
different frames. It is not yet a general application-buffer/client-target
test, a 30-minute soak, a high-refresh validation, or a claim of production
stability. The QEMU test process was shut down after the run; its host-side
serial and stderr logs remain in `aosp/windows-arm64-test/` on host 106.
