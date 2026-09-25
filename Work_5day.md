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

### W5-ANDROID-APK-WINDOW-V32-20260924
- Built `framework-minus-apex` incrementally on host 185 after omitting only the optional `TetheringManager` registry entry; Soong completed 123 steps successfully. The fresh `framework.jar` was installed at 2026-09-24 10:57 CST. Repacked a unique v32 EROFS image with the native-window test APK; remote and Windows SHA-256 matched: `187bdf3303a21e26d1b06f38fff9ab03539a1268ac8182ad414438ff4264f40d`.
- Booted v32 on local Windows host 106 with upstream QEMU/WHPX and HWC client mode. ADB became online, but the actual maximized QEMU desktop capture (`%TEMP%/kiki-v32-desktop-observation.png`) remained black; no APK Activity appeared. The serial log records `KIKI-ART boot class missing Landroid/util/StatsEvent;` followed by a fatal `NoClassDefFoundError` in `system_server`. The Close button and Activity lifecycle therefore remain untested; this was not a UI success.
- Shut QEMU down promptly through its monitor after the observation. Confirmed PID 13336 exited and TCP monitor port 4446 closed; the remaining ADB `offline` entry is only the disconnected transport.
- Follow-up diagnosis: the built image contains 38 system APEX payload files; bootstrap logs scanned 41 preinstalled APEXes but activated only five bootstrap packages at ~6.59s. The system-server class failure occurs shortly afterward. The product `init.rc` still contains the Kiki-specific skipped APEX-readiness section before `derive_classpath`; the repacker injects an `apexd.status=activated` wait, but v32 shows this is not yet a sufficient runtime classpath guarantee. Next, verify the actual APEX activation/classpath ordering and fix only that integration/repack path before another short UI test; no full AOSP rebuild is indicated yet.

### W5-ANDROID-APK-WINDOW-V34-20260924
- Repacked and booted v34 on Windows host 106, using the updated APEX/classpath gates. Root ADB confirmed `apexd.status=activated`, `kikiaosp.classpath.ready=1`, and `/data/system/environ/classpath` exists (5,220 bytes, including the StatsD framework JAR on `BOOTCLASSPATH`). This corrects the v32 assumption that the file itself was absent.
- The UI test still failed: the maximized QEMU desktop capture `%TEMP%/kiki-v34-desktop-final.png` is black; Android never exposed the `package` service, so the test APK could not be launched. Runtime logs still report `KIKI-ART boot class missing Landroid/util/StatsEvent;`, followed by a fatal `NoClassDefFoundError` in `system_server`; zygote also reports missing framework boot classes. APEX/classpath readiness alone is therefore insufficient, and no APK window or Close-button behavior was demonstrated.
- Ended the test promptly through the QEMU monitor. Confirmed PID 21452 exited, no v34 QEMU process remained, and TCP monitor port 4446 was closed; the maximized desktop window is no longer open. Next, inspect the effective zygote `BOOTCLASSPATH`/ART boot image and verify the referenced framework JARs are actually present and readable before another UI boot attempt.

### W5-ANDROID-APK-BCP-DIAGNOSTIC-20260924
- Reopened the existing v34 image only for a short root-ADB diagnosis, then closed QEMU via the monitor (PID 19804 exited; port 4446 closed). The live zygote environment had 52 `BOOTCLASSPATH` entries; every listed path was readable. Runtime mounts included the StatsD, Bluetooth, and TelephonyCore APEXes, and the mounted `framework-statsd.jar` was present. Its DEX contains `Landroid/util/StatsEvent;`, yet ART still failed to resolve it; the PackageManager service remained unavailable. This narrows the failure to ART's actual loaded boot-class-path state rather than a missing APEX file or environment export.
- The v34 boot log also exposed `Invalid keyword 'setprop'` in `init.zygote64.rc`: `kikiaosp.ignore_apex_versions` had incorrectly been placed inside the zygote service stanza. Corrected the canonical AOSP patch and repack script to remove that invalid service option and set the property from `on early-init` instead.
- Added temporary, StatsEvent-only ART diagnostics to print the internal `boot_class_path_` count and DexFile locations on lookup failure. Started the incremental `m -j8 com.android.art` build in the existing `kiki-hwc-guest` tmux session, window `apk-v9-repack`; no full AOSP image build is running.

### W5-APK-PATCH-AUDIT-20260924
- The v38 serial log exposed `SetupMountNamespaces failed: Invalid argument`; the earlier Kiki-specific skip of `/apex` and `/bootstrap-apex` tmpfs setup was the cause. Restored the standard mountpoint setup in `system/core/init/init.cpp`, removed the late `/apex` remount from `init.rc`, and retained apexd readiness before `perform_apex_config`.
- Auditing the source handoff found overlapping patch artifacts: several separate HWC/render patches edited files also present in `aosp-working-tree.patch`, and the old dma-buf patch no longer reverse-applied cleanly. Regenerated the active patch set from the current AOSP tracked diff and partitioned it by file owner: 149 main files, 4 render-output, 1 SurfaceFlinger diagnostic, 1 guest-composer, and 1 device-buffer file (156 unique tracked files total). Archived the superseded overlapping dma-buf intermediate rather than applying the same file twice.
- Updated the integration and audit scripts. The audit now verifies the exact 156 tracked paths, the 5 intended overlays, and reverse-dry-run success for every active patch. It passes on `/home/keke/aosp-master`.
- Four untracked `.orig`/`.pre-*` scratch backups in AOSP were verified as duplicate snapshots and moved intact to `/tmp/kikiaosp-aosp-audit-backups-20260924`; nothing was discarded. No QEMU process/window or build is currently running.
- Next: build only the affected init target/artifacts, repack a fresh test image, launch QEMU maximized for one observation, and close it immediately after the test. The APK Activity and its Close button remain unverified; the goal is a native Android app window, not merely a host/QEMU dialog.

### W5-ANDROID-APK-WINDOW-V39-20260924
- The targeted AOSP build completed successfully in 23 seconds (`init` + `init.rc`, 11 steps). Repacked v39 with the new Android init binary; local and remote system-image SHA-256 matched (`d70c9e06ae518c9fda2e5b848e859eeba569a454adc8784066284f0a50745cb5`). The other three partitions also matched their remote hashes.
- Local Windows QEMU/WHPX v39 boot reached ADB and `apexd.status=activated`. The prior invalid init keywords were gone, but `SetupMountNamespaces` still failed with `No such file or directory`: the stable root image lacked the `/bootstrap-apex` mountpoint. `mount_all` also had no `/vendor/etc/fstab.ranchu` because the product copied that file only to `/system/etc`; therefore `/data` stayed read-only, and zygote repeatedly aborted trying to create `/data/dalvik-cache/arm64`. PackageManager and the APK Activity did not start.
- Ended v39 through QEMU monitor `quit`; confirmed PID 4968 exited and port 4446 closed. A desktop screenshot was not captured because Chrome was the foreground application; do not treat this run as visual UI evidence.
- Corrected the canonical device product fstab destination to `vendor/etc/fstab.ranchu`. Updated the APK repacker to stage that fstab into the vendor image (using the current system copy as a fallback until the next Soong graph refresh) and create `/bootstrap-apex` before building the root image. These changes address both observed failures without touching upstream AOSP sources. Next test is a unique v40 image; no full AOSP build is needed for the packaging-only fix.

### W5-ANDROID-APK-WINDOW-V40-20260924
- v40 included `/bootstrap-apex`; the previous mount-namespace failure disappeared and servicemanager successfully loaded `/bootstrap-apex/apex-info-list.xml`.
- ADB still showed `/data` read-only and PackageManager absent. The v40 serial log proved why: `/vendor/etc/fstab.ranchu` was present, but both `/init.ranchu.rc` and `/vendor/etc/init/hw/init.ranchu.rc` imports failed because the vendor init rc was not packaged. Consequently its `mount_all` actions never ran and userdata stayed unmounted; zygote then failed on the absent `/data/dalvik-cache/arm64`.
- Closed v40 via QEMU monitor; confirmed PID 9828 exited and TCP port 4446 closed. No APK window was reached.
- Added a minimal Kiki-owned `init.ranchu.rc` containing only early/late fstab mount actions, packaged it beside the vendor fstab, and changed `/data` to `latemount` so it is mounted in the late-fs phase. The product makefile and repacker are updated; the AOSP device-tree copy is kept byte-identical to the canonical repo. Next: package-only v41, then test whether userdata mounts and PackageManager reaches the APK. No Soong/AOSP rebuild is needed for this change.

### W5-ANDROID-APK-WINDOW-V47-TO-V50-20260924
- v47 (`796280a735acf74fa0be81d413915bb6e7bc0ed175cf54c47b6db4cd6c9ce79d`) extended the static ART namespace allowlist; ART runtime initialization advanced but then failed resolving `libstatspull.so`. v48 (`804589324247ff16d332413822262022ac19a0f1e641dd1098fcf4c27e357e3c`) loaded ART and completed `Runtime::Start`, then crashed in `JVM_NativeLoad` from StatsLog because system and ART-APEX copies of `libart.so` created separate Runtime singletons. v49 (`8fb6fec6a41dde2fd2c1abbe717e5a04a2911e15b8337c0fbbcb2f8ff0dd76d7`) proved JNI was loading `/apex/com.android.art/lib64/libart.so`; it next failed to load `libartpalette-system.so`.
- v50 (`3527b5647115be5e2c3754b74703dbe1c6fa8271ad19d8fcf8f5f19781dbd293`) added the palette/system links to the static config but failed because replacing the entire runtime-generated linkerconfig removed current Android 17 APEX namespaces, including `com_android_tethering`. System_server and PackageManager did not start; no APK Activity or UI was reached.
- All v47–v50 QEMU windows were terminated via monitor after collecting each failure. No result in this range demonstrates an Android UI.

### W5-ANDROID-APK-WINDOW-V51-20260924
- Removed the stale `ld.config.kiki.txt` copy from the repacker and product makefile. AOSP source confirms `perform_apex_config` regenerates `/linkerconfig/ld.config.txt` after `apexd.status=activated`; v51's live config included current namespaces such as `com_android_tethering`, and the v50 missing-namespace error was gone. Reverted the temporary ART allowlist additions to the unused static file.
- Repacked v51 from the frozen bufferqueue base. SHA-256 on host 185 and Windows 106 matched: `e20f5df2ec99d1a72f0c7dc89bd9c3015124fdbea229c2679d44f9731069cf27`. Vendor/product/system_ext hashes matched the v41 reference exactly, so only the new system image was transferred.
- v51 reached ADB, but zygote repeatedly aborted at `dlopen failed: library "libart.so" not found`; the generated dynamic config exported only `libjdwp.so` from the ART APEX to the default namespace, despite `libart.so` being present inside that APEX. Independently, `vendor.hwcomposer-3` hit `DRM_IOCTL_MODE_CREATE_DUMB` allocation failure and null-dereferenced in `DrmSwapchain::getNextImage`, causing SurfaceFlinger to abort. PackageManager remained unavailable; no APK UI was reached. Windows desktop capture was not obtained because Chrome retained foreground focus; no visual success is claimed.
- Closed the maximized QEMU promptly through monitor `quit`; verified PID 25392 exited and host ports 4446/5555 were closed, then disconnected ADB.
- Added `libart.so` to the release ART APEX `provideNativeLibs` declaration in the device-owned AOSP patch set. The complete AOSP/device-tree audit still passes (156 tracked patch paths, 5 overlays). An incremental `m -j8 com.android.art` build is running in the existing `kiki-hwc-guest:ui-core-build` tmux window. Next: install the rebuilt ART APEX into a unique v52 image and verify zygote/PackageManager first; handle the independently observed HWC allocation crash from its evidence. Keep QEMU tests short and close each maximized window immediately after the result.

### W5-ANDROID-APK-WINDOW-V52-20260924
- `m -j8 com.android.art` succeeded (11 Ninja steps; Soong graph analysis took about 3:51). `deapexer info` confirmed the installed ART APEX advertises `libart.so` and its runtime dependencies. Repacked v52; remote and Windows SHA-256 matched: `3da2219a42d1bea27b098a69e07bb15432002be72b90a3257eee23537e61c065`. Vendor/product/system_ext hashes remained identical to the v41 reference.
- Tested with `HwcMode=client` based on the v51 `GuestFrameComposer` swapchain-allocation crash. In v52, `vendor.hwcomposer-3` and SurfaceFlinger stayed running; the guest swapchain crash did not recur. Zygote still aborted at `dlopen failed: library "libart.so" not found`, and PackageManager was unavailable; the APK UI was not reached.
- The current APEX was active and mounted. Runtime `/linkerconfig/ld.config.txt` still listed only `libjdwp.so` for the default-to-ART link. Source inspection of Android 17 `system/linkerconfig/modules/apex.cc` and its README shows APEX exports are intersected with `/system/etc/public.libraries.txt`; adding the APEX manifest entry alone is insufficient because `libart.so` is absent from the system public-library list.
- Closed QEMU through monitor `quit` promptly; verified PID 11664 exited and ports 4446/5555 were released, then disconnected ADB. Next: add only `libart.so` to the Kiki AOSP product's system public-library list through the device-owned patch set, build that small artifact, repack a unique v53, and retest with client HWC. No UI success is claimed.

### W5-ANDROID-APK-WINDOW-V53-V54-20260924
- v53 tested the system-public-library route for exposing `libart.so`. It changed the app-facing/public-library configuration but did not add `libart.so` to the platform default-to-ART linker namespace; zygote still did not start and no APK UI was reached. Reverted that experiment from both the repacker and AOSP patch set. This establishes that the public library list is the wrong control for this platform linker edge.
- v54 first used `userdata-qemu-fresh.img`; its serial log showed `/data` was not mounted read-write, post-fs-data directory creation failed, and zygote could not create dalvik-cache. This run is not valid evidence about the linker fix. Closed QEMU PID 11516 immediately after diagnosis; monitor and ADB ports were released. No desktop screenshot was captured because Chrome retained foreground focus.
- Re-tested the same v54 system image with the previously mountable `userdata-kikiaosp17-f2fs.img`. `/data` mounted F2FS read-write, and the live linker config now exposed `libart.so` from the ART APEX to the default namespace. ART then advanced to loading `libicu_jni.so` and failed because `libicuuc.so` was not available inside `com_android_art`; PackageManager and the APK remained unavailable. Closed PID 19132 through the QEMU monitor and verified QEMU was gone and port 4446 was released.
- Restored the standard Android 17 system `requireLibs` entries instead of keeping the earlier broad removals, adding only Kiki's needed `libart.so`. A normal `m systemimage` dependency graph unexpectedly announced 101,387 actions, so it was interrupted after 49 seconds rather than allowed to turn into a full rebuild. The affected generated linker protobuf was updated narrowly with AOSP's `conv_linker_config` tool; the follow-up system image was repacked from the existing frozen base.

### W5-ANDROID-APK-WINDOW-V55-20260924
- Synced release and debug ART APEX manifests: both declare `libart.so` as provided and require the ICU libraries (`libicuuc.so`, `libicui18n.so`) needed by ART's `libicu_jni.so`. Restored the upstream system linker library set and added `libart.so`; audit passes with 157 tracked AOSP patch paths and 5 overlays.
- The targeted `m -j8 com.android.art` build succeeded in 17 seconds (11 Ninja actions). Repacked v55; system-image SHA-256 on host 185 and Windows 106 matched: `e54a4635a22333bd8df69bb322f1226e506448a29642f1c1524a5c414db09704`. Vendor/product/system_ext hashes remained identical to the v41 reference.
- With the correct F2FS userdata, v55 mounted `/data` read-write and the live config showed the expected default-to-ART and ART-to-i18n namespace links, including `libicuuc.so`. SurfaceFlinger remained running, zygote initialized ART and forked system_server, but system_server aborted at `selinux_android_setcontext(1000, 1, null, null)` with the libselinux diagnostic “Out of memory.” The package service never appeared, so the test APK was not launched and no native app window/Close button was demonstrated. Closed PID 15620 promptly; confirmed no QEMU process remained and port 4446 was released.
- A short follow-up passed `selinux=0` through the QEMU kernel command line. The 7.3-rc4 kernel explicitly logged it as an unknown command-line parameter and still initialized SELinux; system_server failed at the same context transition. Closed PID 20116 and disconnected ADB. Therefore this was not a successful SELinux-disabled test. Next: inspect the device's compiled seapp/SELinux policy and kernel config to determine whether the generic “Out of memory” is a context-range/policy error or an actual allocation failure; do not claim SELinux is disabled. Every maximized QEMU test window in this sequence was closed through the monitor at test end, with process/port checks.

### W5-SELINUX-AVC-ACCESS-DIAGNOSTIC-V61-20260924
- Corrected the SELinux AVC diagnostic patch so its log statements do not change the original `if (rc) goto out` control flow. The v60 diagnostic had inserted an unbraced log between those statements, making `goto out` unconditional and bypassing AVC cache insertion on misses; treat v60 behavior as invalid diagnostic evidence. The v61 patch was reverse-dry-run checked and the full AOSP integration audit passed (158 tracked patch paths, 5 overlays).
- Built only `libselinux` (`m -j8 libselinux`, 48 actions, about 1:25), then repacked v61 from v59. The system image SHA-256 is `43b1d3a56cb0b66deee8b735b527a4b4f60c98a4f51407d7468f15a9d2e4728e`. The unchanged vendor/product/system_ext images match the known v57 partition hashes.
- The v61 serial diagnostic confirmed userspace and kernel both report permissive (`enforcing=0`), but `security_compute_av_flags_raw()` returned `-1`; the outer diagnostic printed `errno=2` and `selinux_mnt=/sys/fs/selinux`. Because libselinux does not set `errno` on every later failure path (notably response parsing), this errno may be stale and does not prove that `open(/sys/fs/selinux/access)` failed. The maximized Windows QEMU screenshot is `aosp/windows-arm64-test/qemu-desktop-v61-selinux-diagnostic-fixed-20260924.png`; it shows a black guest display, not the APK window.
- A second short, audit-disabled v61 boot was used only to recover guest state through ADB. ADB remained `offline`; the serial log shows `hwservicemanager` aborting after a SELinux property check, `zygote` repeatedly killed, and SurfaceFlinger restarted. No package service or APK Activity was reached. Closed QEMU PID 17288 via its monitor and confirmed ports 4446/5555 were released. The no-audit serial log SHA-256 is `90eb24154a101c7cb550919a26eb8d40881a273c376737c4e29477e7cb366a74`.
- Upstream Linux v7.3-rc4 `security/selinux/selinuxfs.c` unconditionally registers `/access` in the selinuxfs root, while libselinux opens `${selinux_mnt}/access`; see https://github.com/torvalds/linux/blob/v7.3-rc4/security/selinux/selinuxfs.c and https://github.com/SELinuxProject/selinux/blob/main/libselinux/src/compute_av.c. This is the expected upstream interface, but the guest's ADB-offline state prevented directly listing `/sys/fs/selinux`; instrument the individual libselinux open/write/read/parse stages before concluding that the kernel endpoint is missing.
- Kernel provenance audit found a reproducibility gap: Windows used `kernel-linux-7.3-rc4-4k` (SHA-256 `f44cb82d82655309d3039f4c9706f60d6d0d66bab081b78850625b3c2c879662`), but `/home/keke/projects/kikiaosp_kernel` on host 185 is at `3f6f2c9` and its committed flake still declares version `7.3.0-rc3-kikiemu-4k` with source `./linux-7.3-rc3-src`; no rc4 source/build recipe was present there. This is a separate reproducibility gap, not yet a demonstrated cause of the AVC failure. The validated native KMS/HWC `TEST OK` v3 remains the graphics baseline; it is not proof of an Android APK Activity.
- Next gate: build only a diagnostic `libselinux` with stage-specific results for mount selection/open/write/read/response parsing, boot the same v61 base once, and close QEMU after the serial result. In parallel, recover the exact rc4 kernel source/config provenance before attributing the issue to the kernel. Do not run another full AOSP build or add framework/SELinux workarounds before these facts are known. After AVC queries and core services remain healthy, build the APK target separately, install/launch it through ADB, and visually verify animation plus its in-app Close button.

### W5-SELINUX-AVC-STAGE-DIAGNOSTIC-V62-V63-20260924
- v62 did not contain all of the stage-specific callsites even though its `libselinux.so` contained the diagnostic format string. The AOSP integration patch had been only partially applied: its helper and mount-pointer branch were present, while open/write/read/parse branches were absent. GNU `patch` treated the partially applied file patch as already applied and skipped its remaining hunks; the previous reverse-dry-run audit also accepted that partial state. Therefore v62's missing stage line was not runtime evidence about the SELinux endpoint.
- Added a completion patch for the missing failure branches and strengthened `audit-aosp-integration.sh` to check all seven required stage markers explicitly. The complete AOSP integration audit now passes with 159 tracked patch paths and 5 overlays. Only `libselinux` was rebuilt (`m -j8 libselinux`, 43 Ninja actions, about 11 seconds); no full AOSP or kernel build ran.
- Repacked v63 from the frozen v59 base. The system-image SHA-256 is `0b26c1ba83244e658bdc9d61b59a1b977949f08a72ad89ed25dfc014e3543bb9`; host 185 and Windows 106 hashes match. Its embedded `/system/lib64/libselinux.so` matches the fresh build (`78b2b7f1de35fa167a0c62c663d596290bcd316b976775ac36cdb0c286d43087`). Vendor/product/system_ext are unchanged from v57 (`b886192c…`, `87b36b94…`, `9b437a16…`).
- One v63 QEMU boot on Windows host 106, using the rc4 kernel/ramdisk, v57 supporting partitions, client HWC, 640x480 virtio-gpu, and `audit=0`, now reports the exact failing stage at 6.125s: `stage=open rc=-1 errno=2 path=/sys/fs/selinux/access`. This identifies `ENOENT` from opening that path; it is no longer an inference from possibly stale errno. It does not yet distinguish a missing selinuxfs mount/path from a different kernel filesystem implementation. Init had loaded policy earlier, while upstream Linux v7.3-rc4 source registers `access` in the selinuxfs root, so the remaining discrepancy is below the APK/UI layer. No PackageManager or test Activity was reached; no Android APK window is claimed.
- The Windows screenshot helper could not verify QEMU as foreground because Chrome retained focus, so no screenshot is recorded as evidence. QEMU PID 20220 was shut down through HMP `quit`; no QEMU process or listener remains. Serial log: `aosp/windows-arm64-test/qemu-kikiaosp-v63-selinux-stage-20260924.log`.
- Kernel-source audit found GitHub `main` has advanced to `101444a3717c1f1251d586572975853ad1bf3aea` (“build: make rc4 kernel flake reproducible”), which pins upstream Linux source revision `dec005ae90a2946656a090f37bf1cfbd22f08e57`; the 185 checkout is still at parent `3f6f2c92343113e840ab676d105b979348488c00` (rc3 flake). The existing Windows rc4 Image hash is `f44cb82d82655309d3039f4c9706f60d6d0d66bab081b78850625b3c2c879662`, but its build provenance is not yet tied to the newly pinned recipe. No kernel build was started: the established assignment keeps kernel builds on host 130, which is currently off, while 185 is reserved for AOSP.
- Next gate: establish the exact running kernel source/config provenance and verify whether the guest's `/sys/fs/selinux` mount is really selinuxfs before changing Android policy or framework code. The reproducible rc4 recipe is now identifiable, but validating it requires the designated kernel-build host to be available (or an explicit change to the host assignment). Once the selinuxfs access query works and core services/ADB are healthy, return to the APK Activity and its animated frames/Close button. No APK UI success is claimed.

### W5-ANDROID-APK-WINDOW-V66-V68-20260924
- Continued from the v63 stable display/ADB baseline. v66's SELinux failure was traced to PID 1 unsharing its mount namespace while its property-service threads still used the old `fs_struct`; Linux 7.3 exposes a null mount view to those sibling threads. The opt-in `ro.kikiaosp.single_mount_namespace=true` avoids this PID-1-only failure while retaining SELinux. v67 was first booted with the wrong boot argument (`androidboot.hardware.display_finder_mode=drm`); corrected QEMU argument is `androidboot.hardware.hwcomposer.display_finder_mode=drm`, after which Ranchu HWC found its DRM display and software-vsync path.
- Restored Android 17's `DeviceStateManagerService` in the Kiki patch set because WindowManager needs the global device-state service. Android's default device-state policy/provider can report a default state without a phone hardware HAL. Built only the `services` target in the existing host-185 tmux session: 4,699 Ninja actions, success in 25:35; no `systemimage`/full AOSP or kernel build. The AOSP integration audit passed (160 tracked patch paths, 5 overlays). Repacked v68 from the frozen v67 image; host-185 and Windows-106 system-image SHA-256 match at `9d0b94a1cf3ebe4eecbe6647e78c64d9bd22b9d1032ea0dc821d30979fe0ad72`; vendor/product/system_ext remained unchanged (`b886192c…`, `87b36b94…`, `9b437a16…`).
- v68 confirmed ADB and package discovery (`pm path com.kikiaosp.windowtest` returned `/system/app/KikiWindowTest/KikiWindowTest.apk`); zygote and system_server started. It did not reach `sys.boot_completed`, and `am start` returned `Too early to start activity`; no APK Activity/UI is claimed. SurfaceFlinger repeatedly aborted during Android's startup shader-cache prewarm: minigbm's `DRM_IOCTL_MODE_CREATE_DUMB` returned `EACCES`, 384×384 `HW_RENDER|HW_TEXTURE` allocation failed (`-ENOMEM`), then SurfaceFlinger reported `output buffer not gpu writeable`. The stack is `drawSolidLayers -> Cache::primeShaderCache`; setting only `debug.sf.prime_shader_cache.hole_punch=false` correctly skipped the hole-punch variant but allowed the next solid-layer prewarm to hit the same allocator failure. Android 17 source has an outer `service.sf.prime_shader_cache` gate, default true; next image will set that gate false while preserving ordinary on-demand frame composition. BootAnimation also logged `AssetManager::addDefaultAssets` aborts; reassess only after SurfaceFlinger is stable.
- The first Windows desktop capture (`qemu-desktop-v68-first-boot.png`) showed the terminal, not QEMU. The launch script had started the Console-subsystem QEMU with `WindowStyle Hidden`, hid its GTK/GDK top-level, and selected a `GDI+ Hook Window` as if it were the display. Do not treat that capture as visual evidence. A separate minimal QEMU GTK smoke test proved `ProcessStartInfo.CreateNoWindow=true` plus attaching foreground input and raising the exact `gdkWindowToplevel` works without a console window; screenshot `qemu-window-smoke2-20260924.png` shows the actual maximized QEMU GTK window (`QEMU [Paused]`) in the Windows desktop. This only validates the host window launcher, not Android rendering. The v68 Android QEMU was closed after collecting logs; no QEMU process or monitor/ADB listener remains.
- Next: update the local Windows runner to use the verified no-console GTK launch/focus path; update only the Kiki product/repack properties to disable the complete optional shader prewarm; audit and repack a unique v69 from v68 without a full rebuild, transfer/hash-verify it, then perform one short foreground Windows-desktop test. Gate success on SurfaceFlinger remaining registered/running, `sys.boot_completed=1`, `am start` opening the preinstalled APK, and a screenshot of the actual QEMU window showing at least two animation frames and the app Close button. Stop QEMU promptly; if it still fails, investigate the minigbm DRM dumb-buffer `EACCES` path rather than adding unrelated Android services.

### W5-ANDROID-APK-WINDOW-V70-V71-20260925
- v70 was repacked from v69 without Soong/kernel compilation. Its system image SHA-256 is `9e66299cca33dce1f416694e921f28e95c497898e0950b9e909ca98ba82b95b7`; vendor/product/system_ext exactly match v69. The `trigger nonencrypted` action worked: SurfaceFlinger remained alive and reported HWC display 0 (`EMU_display_0`), while `system_server` started. `installd` then repeatedly exited with `Could not find ANDROID_ROOT`; live inspection showed `/init.environ.rc` was absent from this repacked root.
- The v71 repacker now explicitly stages the Kiki init policy and exports the standard AOSP early-init environment set (`ANDROID_ROOT`, `ANDROID_DATA`, assets/storage, ART/I18N/TZ roots, external storage and ASEC mountpoint). v71 SHA-256 is `89367932e25664de3f3afdc46ca05179dbe1acd694d34f50ce190841cc988479`; all three supporting partition hashes remain identical to v69. On Windows 106, `installd` stayed running; PackageManager and ActivityManager registered, and `pm path com.kikiaosp.windowtest` found the preinstalled APK. This still did not reach `sys.boot_completed`; `window` service was absent and the actual Windows desktop capture was fully black. No Android UI success is claimed.
- A root-only diagnostic backtrace of system_server PID 364 identifies the next blocker, not a guess: `DeviceStateProviderImpl.setStateConditions` unconditionally calls `Context.getSystemService(SensorManager.class)` even with zero configured sensor conditions; native `SensorManager` waits in `waitForSensorService()` for `ISensorServer`. The minimal profile correctly leaves sensor hardware disabled, so `DeviceStateManagerService` construction never returns and SystemServer never reaches WindowManager. The failing call stack was `SensorManager::waitForSensorService -> SystemSensorManager.<init> -> DeviceStateProviderImpl.setStateConditions -> DeviceStateManagerService.<init>`.
- The smallest fix is an AOSP-owned conditional around SensorManager creation/registration when `sensorsToListenTo` is non-empty. It preserves the no-sensors minimal product and leaves all sensor-enabled configurations unchanged. The patch is carried as `patches/aosp-device-state-lazy-sensors.patch`; the integration audit now passes with 161 tracked AOSP paths and 5 overlays. Incremental `m -j8 services` succeeded in the existing host-185 tmux window in 1:31 (178 Ninja steps); no full AOSP or kernel build ran. Repacked v72 from v71; its system SHA-256 is `72e3547434422578e146f040060031a35c135a8a801a20becb6d8b307934d278`, and vendor/product/system_ext hashes remain unchanged from v69. Next transfer/hash-verify v72 and test whether WindowManager starts with sensors still disabled.
- Windows desktop evidence is saved as `qemu-desktop-v70-nonencrypted-init.png` and `qemu-desktop-v71-standard-init-env.png`; corresponding UART logs are `qemu-kikiaosp-v70-nonencrypted-init-20260925.log` and `qemu-kikiaosp-v71-standard-init-env-20260925.log`. Both QEMU test processes were closed and the forwarding/monitor ports released.

### W5-MINIMAL-ANDROID-UI-BOOTSTRAP-V73-V75-20260925
- Checked the suspected `settings` failure against both source logs and the built package tree. `SettingsProvider.apk` (541,767 bytes), Settings, Launcher3QuickStep, and SystemUI are present in the product output and are not excluded by `KIKI_NONCORE_PACKAGES`. v73 PackageManager lookups found SettingsProvider, Launcher3QuickStep, and SystemUI at their expected runtime paths. The blocker is boot ordering/context, not a missing APK, so no broad package restoration was needed.
- v73 made `installSystemProviders()` unconditional while retaining the optional DeviceConfig service gate. Incremental `m -j8 services` succeeded (13 Ninja steps, 1:11). System image SHA-256: `3f4dd361bf5d3faabd3e89945d5c4a7a5ca8bcc1c38032e093ca95845c6d8942`; vendor/product/system_ext match the stable baseline (`b886192c…`, `87b36b94…`, `9b437a16…`). The Windows desktop capture `qemu-desktop-v73-settings-provider-order-early.png` is black. Log evidence shows the previous “system provider not installed” failure is gone, but `ActivityManagerConstants.start()` then failed because `ContentResolver` had no published `IContentService`; Kiki minimal mode had also skipped `ContentService` (and its declared prerequisite, AccountManagerService). QEMU PID 6872 was closed; ports 4447/5555 were released.
- v74 restored the AOSP AccountManagerService → ContentService → system-provider order. Targeted `m -j8 services` succeeded (13 steps, 1:08). System image SHA-256: `6590c3936990d4e7921323c797aca98b3e6d35209e76ca0a0d27b952ddd63224`; supporting partitions remain byte-identical to baseline. This exposed the next direct cause: `ActivityThread.installSystemProviders()` received a null initial Application because the Kiki `ActivityThread.attach(true, 0)` branch explicitly skipped `initializeSystemThread()`. All provider contexts were therefore unavailable; `SettingsProvider.<clinit>` then threw when `Settings.Global.getPublicSettings()` dereferenced `ActivityThread.currentApplication()`. This is why the APK was present but still could not initialize.
- v74 desktop capture: `qemu-desktop-v74-contentservice-bootstrap-early.png`; UART log: `qemu-kikiaosp-v74-contentservice-bootstrap-20260925.log`. QEMU PID 15696 was closed after the failure was identified; no Android UI or WMS success is claimed.
- v75 narrowly adds an explicit system-Application initializer after `SystemServer.createSystemContext()` has established the real system context; it leaves ThreadedRenderer skipped and preserves the required content/provider services. The AOSP integration audit passes with 161 tracked patch paths and 5 overlays. Targeted `m -j8 framework-minus-apex services` is running in the reused `kiki-hwc-guest` tmux window; no systemimage/full build or kernel build was started.
- Next gate: finish the two-target incremental build, repack from frozen v74, hash-verify, and make one foreground Windows QEMU test. Verify `window`, `statusbar`, and `notification`, `sys.boot_completed`, and PackageManager paths before starting the stock HOME/Settings and test APK. Capture the actual desktop and stop QEMU immediately after the test; only claim UI success if it is visibly rendered.

### W5-MINIMAL-ANDROID-UI-BOOTSTRAP-V76-V77-20260925
- Rechecked the reported `settings` error against the v76 boot and v77 package inventory. It was not a missing Settings APK: `/system_ext/priv-app/Settings/Settings.apk`, `/system_ext/priv-app/Launcher3QuickStep/Launcher3QuickStep.apk`, `/system_ext/priv-app/SystemUI/SystemUI.apk`, and `/system/priv-app/SettingsProvider/SettingsProvider.apk` are present. The earlier provider failure was first due to system-provider ordering/context and then missing `/data/user_de/0`; v76 restored `init_user0`, whose `vdc --wait cryptfs init_user0` completed successfully. SettingsProvider then initialized and the previous provider startup errors disappeared. No Settings/Launcher/SystemUI package restoration was needed.
- v76 next stalled during WindowManager bootstrap. Its system_server trace points to `SensorManager::waitForSensorService()` from `WindowOrientationListener` → `DisplayRotation` → `DisplayContent` → `ActivityManagerService.setWindowManager`; sensor services remain intentionally disabled. This is a sensorless display-rotation initialization problem, not a Settings failure.
- v77 added a Kiki-owned AOSP guard so DisplayRotation omits the orientation listener when `config_supportAutoRotation=false`, plus a product resource overlay setting that value false. `m -j8 services framework-res` succeeded (38 Ninja steps, 1:46); no full image or kernel build ran. The build generated the vendor RRO. Repacked v77 SHA-256: `22fa03e49796670e496d00cf636f15ca35c01d5b352e81f7c6ac09febc263668`.
- The first v77 run used v65 vendor/product/system_ext partitions because the local runner hard-coded those sidecars. Updated the runner to select same-stem sidecars; transferred the v77 partitions and verified their SHA-256s against host 185 (`de303e…`, `87b36b…`, `9b437a…`). The matched-partition retest remained black; ADB found `window`, but not `statusbar` or `overlay`, and `sys.boot_completed` stayed unset. Source-order inspection found the specific reason the RRO cannot take effect: Kiki's `SystemServer.startBootstrapServices()` starts `OverlayManagerService` only when `ro.kikiaosp.overlay_manager=true`; the Kiki product/repacker do not set this property, so the default path skips OverlayManagerService before WindowManager construction. Consequently the `config_supportAutoRotation=false` RRO is not applied and `DisplayRotation` still tries to connect to the absent sensor service. This is a startup-configuration gate, not missing Settings/UI APKs.
- Windows desktop captures: `qemu-desktop-v77-no-auto-rotation-sensor-early.png` (mismatched sidecars; diagnostic only) and `qemu-desktop-v77-matched-partitions-early.png` (matched sidecars; still black). UART logs are `qemu-kikiaosp-v77-no-auto-rotation-sensor-20260925.log` and `qemu-kikiaosp-v77-matched-partitions-20260925.log`. Both QEMU processes were stopped through HMP `quit`; confirmed no QEMU process and ports 4447/5555 clear. No Android UI success is claimed.
- Next: leave Settings/Launcher/SystemUI package selection unchanged. Enable `ro.kikiaosp.overlay_manager=true` only for the Kiki product (including the repacker's test property), then do a short matched-partition boot. Verify OverlayManagerService is published, `config_supportAutoRotation=false` takes effect, and the SystemServer main thread passes WindowManager construction before proceeding to status bar or launcher validation.

### W5-SETTINGS-PACKAGE-AUDIT-UI-STARTUP-V98-20260925
- Rechecked the reported `settings` issue against a live v98 boot. PackageManager resolves Settings to `/system_ext/priv-app/Settings/Settings.apk`, SystemUI to `/system_ext/priv-app/SystemUI/SystemUI.apk`, and Launcher3 to `/system_ext/priv-app/Launcher3QuickStep/Launcher3QuickStep.apk`; SettingsProvider is also present at `/system/priv-app/SettingsProvider/SettingsProvider.apk`. The error is not caused by a missing Settings/UI APK.
- The Kiki minimal `SystemServer` path already publishes `StatusBarManagerService` and `NotificationManagerService` and calls the stock `startSystemUi(context, wm)`. No package restoration or additional phone services were needed; v98 logs show PackageManager attempting to start `com.android.systemui`.
- v97 failed before that point because `ModifierShortcutManager` assumed an always-present `RoleManager`, although the minimal profile intentionally skips RoleManager and its supervision dependencies. Added null-safe, logged fallback behavior (role-based keyboard shortcuts disabled only when RoleManager is unavailable) to the AOSP working-tree patch. Integration audit passed with 167 tracked patch paths and 5 overlays.
- Built only `m -j8 services` on host 185; success in 18 Ninja actions / 2:38. Repacked v98 incrementally from v97 without a full system or kernel rebuild. System SHA-256: `12e09e8108581bda58d6de997bbe4a24bfa5ab08b6573b8fd4df5a08eea6408e`; vendor/product/system_ext hashes match v97 (`de303e20…`, `2819a943…`, `967d6388…`). All four transferred partition hashes were verified on Windows.
- v98 passes the former WindowManager/RoleManager crash and reaches stock SystemUI process launch. It does not reach `sys.boot_completed`; no stable Android UI or rendered screenshot is claimed. During app launch, Zygote reports an `ENOENT` bind mount from `/data_mirror/data_de/null/0/com.android.systemui` to `/data/user_de/0/com.android.systemui`. AOSP's Zygote source documents the volume UUID token `null` as the default volume, so the actionable issue is the absent app-data source/setup, not the Settings APK.
- SystemServer then repeatedly crashes in `PackageManagerService.notifyDexLoad` → `DexUseManagerLocal.validateInputs` → `ArtJni.validateDexPath`, with `UnsatisfiedLinkError: failed to create native namespace name:clns-1` (`search_paths=/system/lib64/bootstrap:/system/lib64:/system_ext/lib64`). This is a separate ART/linker namespace blocker exposed after the WindowManager fix; investigate it independently from app-data preparation and UI package inventory.
- The local QEMU GTK window was verified maximized and foreground for v98, then closed through the QEMU monitor after collecting logs. Confirmed no QEMU process and no listeners on ports 4447/5555. No build or QEMU work was moved to host 130.
- Next: keep Settings, Launcher3, and SystemUI package selection unchanged. Trace why user-0 DE app data is absent at stock SystemUI launch and why ART cannot create `clns-1`; only after those are fixed, validate stable SystemUI/status-bar/notification/Launcher startup and capture actual Windows desktop evidence.

### W5-SETTINGS-ERROR-ROOT-MOUNT-AND-MINIMAL-UI-DEPS-V100-V101-20260925
- Revalidated the “Settings error” hypothesis with live PackageManager queries on Windows host 106: Settings, SettingsProvider, Launcher3QuickStep, and SystemUI all resolve to their expected APK paths. `activity`, `package`, `window`, `statusbar`, and `notification` Binder services are also published in the minimal profile. No UI APK/package restoration was indicated.
- v100 was a failed diagnostic attempt: adding `mkdir /data_mirror` to post-fs-data `init.rc` did not work because `/` was already read-only (`EROFS`). The UART log explicitly reports that command failing with `Read-only file system`; the v100 image SHA-256 is `4aaf032b0dc3bb89b24ab0f27eb4e9bae7f3137d3d0e92e4f39feebbb4a50344`. The temporary source change was removed. While refreshing the canonical init.rc patch against the actual AOSP diff, corrected a stale hunk that would have removed the standard recursive `/data` restorecon; the current source retains it. The integration audit passes (167 tracked patch paths, 5 overlays).
- Root-path diagnosis: the supplied gzip/newc initrd does contain a top-level `data_mirror`, but init logs `Switching root to '/first_stage_ramdisk'`, and the runtime mount table shows `/` ultimately mounted from the system EROFS block device `/dev/block/vda`. Thus the active system-image root, not the original initrd root, must contain the `/data_mirror` mountpoint.
- Updated `scripts/repack-services-delta.sh` to add an empty mode-0755 `data_mirror` directory at the extracted EROFS root before rebuilding. Repacked v101 from the frozen v99 base without a full AOSP/kernel build. System SHA-256 is `92c59ecde7b2004435e01231bcd939cf9f7b3ae65f2a3ecc7b1dab3a294c05f0`; vendor/product/system_ext are unchanged (`de303e20…`, `2819a943…`, `967d6388…`).
- v101 runtime confirms `/data_mirror` is mounted as tmpfs and that data/user, data/user_de, misc, and profile bind mounts are present. This fixes the missing-app-data-source failure that had prevented Zygote from binding SystemUI/PermissionController app data. ADB remains available.
- The newly exposed UI failures are service-dependency issues, not absent APKs: PermissionController throws a null `RoleManager` NPE because the Kiki minimal path skips `RoleManagerService`; stock SystemUI's `CustomizationProvider` fails with `IInputMethodManager is not available` because the minimal-services shortcut returns before the normal `StartInputMethodManagerLifecycle` section. `sys.boot_completed` remains unset and WindowManager reports no focused/resumed UI, so Android's native UI is not yet running/rendered. Keep the Settings/Launcher/SystemUI packages unchanged; next analyze the smallest compatible RoleManager/supervision and InputMethodManager dependencies before altering the service graph.
- v99/v100/v101 test logs are retained under `aosp/windows-arm64-test/`. Each foreground QEMU run was stopped through HMP `quit`; final check found no QEMU process and no listeners on ports 4447/5555. No Android UI success is claimed.

### W5-SETTINGS-ERROR-AUDIT-V102-V104-20260925
- Re-audited the reported Settings failure against the built product inventory and the v104 UART run. The package inventory contains Settings (`/system/system_ext/priv-app/Settings/Settings.apk`, 88,030,111 bytes), SettingsProvider (`/system/priv-app/SettingsProvider/SettingsProvider.apk`, 541,767 bytes), SystemUI (`/system/system_ext/priv-app/SystemUI/SystemUI.apk`, 45,481,797 bytes), and Launcher3QuickStep (`/system/system_ext/priv-app/Launcher3QuickStep/Launcher3QuickStep.apk`, 19,806,344 bytes). No APK restoration or package-list change is indicated.
- v104 SystemServer reached boot phases 500, 550, and 600 and logged starts for `StatusBarManagerService` and `NotificationManagerService`; it then called stock `startSystemUi`. Therefore status bar/notification startup is already in the minimal path, not absent from the image. The `settings` ContentProvider is an APK/content-provider endpoint, not a Binder service expected to appear under a `service list` name `settings`.
- The v104 SystemUI error is a startup/dependency failure, not a missing Settings package. At 17.24s, `CustomizationProvider` installation entered `SystemUIInitializer.init()` → `getShell()` and hit `DeadSystemRuntimeException` from `ActivityManager.getCurrentUser()`; init then restarted zygote. Subsequent SystemUI retries showed a Dagger `NullPointerException` in `ReferenceGlobalRootComponent` provider construction. The first reported stack establishes that the system Binder was already dead; the later Dagger NPE is not evidence that Settings.apk is absent. Investigate the earlier SystemServer/zygote restart and the optional Shell dependency chain before adding services.
- v104 remains visually black and does not establish a working Android UI. Its desktop capture and UART log are `aosp/windows-arm64-test/qemu-desktop-v104-systemui-provider-null.png` and `aosp/windows-arm64-test/qemu-kikiaosp-v104-role-imms-ui-inputguard-20260925.log`. QEMU was shut down after collecting evidence; final local check found no QEMU process and no listeners on ports 4447/5555. No package or source changes were made during this audit; no UI success is claimed.

### W5-V105-V106-STOP-PIECEMEAL-BOOT-DEPENDENCY-AUDIT-20260925
- A live v104 crash-buffer recheck found the first system-process exception in RoleControllerService: SystemSupervisionRoleBehavior called a null SupervisionManager. This explains the later SystemUI DeadSystemException; Settings/SettingsProvider/Launcher/SystemUI are installed.
- v105 restored the stock SupervisionService after RoleService and enabled its boot-phase callback. The canonical patch was refreshed and the integration audit passed (169 tracked patch paths, 5 overlays). An incremental services build and repack completed. System image SHA-256: `58dbd9132292128862faa276d3e52ce6a3f8d8dfd114198322f5eddfa4a8b80c`; vendor/product/system_ext stayed byte-identical to v104 (`de303e20...`, `2819a943...`, `967d6388...`). Windows verified the full system hash before boot.
- v105 did NOT fix startup: live `adb logcat -b crash -d` showed repeated system-process RoleController exceptions in DevicePolicyManagementRoleBehavior because DevicePolicyManager was null. The system_server/zygote cycle restarted about every 6-7 seconds; sys.boot_completed remained unset. The actual foreground/maximized Windows QEMU screenshot remained black: `aosp/windows-arm64-test/qemu-desktop-v105-role-supervision-service.png`; UART log: `qemu-kikiaosp-v105-role-supervision-service-20260925.log`. QEMU PID 15080 was closed through HMP quit and no local QEMU/listener remained. The Java fatal stack came from the live ADB crash buffer, not a claim that it was fully captured in UART.
- Before the user's stop-and-audit instruction, v106 source added LockSettingsService and DevicePolicyManagerService before the Kiki minimal phase 500 and added both to the callback allowlist. `m -j12 services` completed in the existing 185 tmux window (24 Ninja actions, 1:35). No v106 image was repacked or booted. These changes remain an unvalidated diagnostic state, not an accepted UI baseline.
- User requested a complete core-dependency checklist and plan before further changes/testing. Accordingly, no next QEMU run or recovery implementation was performed. Read-only comparison against the exact upstream HEAD found structural omissions: the minimal startOtherServices return skips later services; phase 480/520 and explicit ready calls are missing; SystemServiceManager suppresses selected callbacks/errors; DisplayManager.windowManagerAndInputReady is skipped; PowerManager's phase 500 callback is excluded; native init stops netd/audio/KeyMint and bypasses keystore/BPF handshakes. Merely starting DevicePolicy in v106 does not close this graph.
- Added `docs/android17-boot-dependency-plan.md` and `docs/android17-systemserver-startup-inventory.tsv`. The inventory records 263 direct Java startup/registration callsites from unmodified frameworks/base HEAD `94b4c163b7dfe5ce3607f7bb8456f9573f7de57d`; it includes optional/dynamic branches and is explicitly NOT a list of 263 mandatory services or proof of a full runtime dependency graph.
- Proposed recovery: restore standard Framework startup/lifecycle with its upstream feature gates; keep a small user-facing APK set; provide required native/virtual-device endpoints coherently; preserve proven Kiki graphics/platform adaptations; audit final packages/APEXes/VINTF/init/feature/RRO data before a single incremental integration build and matching partition repack. Acceptance remains a real animated APK Activity with Close, Launcher/Settings/SystemUI usable, genuine boot completion, at least 30 minutes of stability, and actual Windows screenshots. No UI success is claimed.

### W5-DEVICE-TREE-CORE-RECOMPOSITION-20260925
- Began the approved one-pass device-tree overhaul from the dependency audit. Replaced broad `aosp_arm64.mk` GSI inheritance plus two overlapping package-minus lists with AOSP `core_64_bit.mk` + `core_minimal.mk`, explicit language/APEX support, and a small UI package set: Launcher3QuickStep, Settings, SystemUI, LatinIME, and the existing animated `KikiWindowTest` APK. The product identity is now “KikiAOSP Test Device”; the old lunch target string remains unchanged for compatibility.
- Changed the product configuration to select the full Framework startup branch (`ro.kikiaosp.bootstrap_only=false`, `ro.kikiaosp.minimal_services=false`) and explicitly enable the gated role/settings, overlay, watchdog, KeyChain, APEX rollback, WebView, and app-usage services. Radio and battery-only services remain disabled because this QEMU target has no such hardware endpoint. Existing proven ARM64, Ranchu HWC3/minigbm/Pastel, fixed-orientation overlay, ADB, fstab, and SELinux configuration are preserved. This sets the product mode; the remaining custom Framework conditionals are still subject to runtime verification.
- Replaced the `kiki-minimal-native.rc` stop-all policy with environment exports only. In particular, it no longer stops `audioserver`, `netd`, graphics, storage, thermal, sensor, or KeyMint services. Kept the historical filename because the current repacker consumes it.
- Made `apply-aosp-integration.sh` delegate device-tree copying to the path-validated, non-deleting sync script rather than recursively deleting the AOSP destination. Added a separate device-profile audit that asserts the positive core/UI composition and rejects native-service stop rules, keeping the existing dirty AOSP integration audit untouched. Updated both READMEs to distinguish the proven black/display baseline from the still-unverified Android Activity UI.
- Kept the current no-APEX framework aliases and their prebuilts explicitly marked as temporary: the tracked ART/app_process patch still references them. Removing them now would repeat the earlier source/device-tree mismatch; replace the ART patch and generated APEX bootclasspath atomically before pruning these files.
- This is a source/configuration checkpoint only. No AOSP build, image repack, QEMU run, or UI success is claimed. Next: review the exact diff and static invariants, synchronize the device tree to host 185, then perform one matched incremental Android build and a local Windows foreground QEMU validation. Acceptance still requires the visible animated APK window, Close action, two distinct desktop frames, and a 30-minute stable run.

### W5-ANDROID17-UI-RUNTIME-CLASS-PATH-POWER-BPF-NETFILTER-20260925
- The new system/vendor image pair was transferred to Windows and SHA-256 checked before boot. Evidence is now collected only after UART/ADB/logcat establish the settled boot stage; the 2880x1920 foreground QEMU desktop captures are stored under `C:\Users\keke\Downloads\temp`, never the Desktop. Every test QEMU PID was stopped after inspection; no UI success is inferred from a startup screenshot.
- The first rebuilt pair exposed two independent early problems: omitted Ranchu boot-property bridging left EGL selection and Dalvik heap limits empty, causing SurfaceFlinger EGL abort and Zygote OOM; and the product omitted `librs_jni`, which Zygote preloads through RenderScript. Restored the upstream-style early-init property bridge in the Kiki device tree, included `librs_jni`, and added audit guards. Incremental vendor/system builds succeeded; matched images were hash-verified on Windows. System `265f2e4027a73689f7628a04ea3a695c4baf58f21067a257e9348bb1071b0760`, vendor `a1449436e0ff10e9171f68bdea85d9ca7b7ab70add69c1e6e032ff9f701635e3`.
- With that pair, Zygote and SurfaceFlinger stayed up, but `system_server` failed in PackageManager with `NoClassDefFoundError: com.android.permission.persistence.RuntimePermissionsPersistence`. The Permission APEX and jar were present; `/data/system/environ/classpath` contained `service-permission.jar`. An old hard-coded `setenv SYSTEMSERVERCLASSPATH` in patched `init.zygote64.rc` overrode the generated classpath. Removed only that stale override from the AOSP working tree and canonical device-repository patch; `audit-aosp-integration.sh` now rejects recurrence. Incremental `systemimage` took 23 seconds. System SHA-256 `89532ca4c47d4b7eadcd28c5a56c0ff8754004cba877c660524fb6c44d8fa875`.
- The next cold boot passed PackageManager and reached HintManager, which dereferenced a null Power HAL `SupportInfo`. Added the same upstream `com.android.hardware.power` virtual APEX used by Goldfish to the Kiki product, without modifying Framework. Rebuilt matching system/vendor in 4:09; SHA-256 system `0c00b02531c0324d41e419649430400016ad4e54d0afc6beb326ecac8da48316`, vendor `d65616c512966fdde2c83a47f47a3cefd8104e90c9cb45fd57a6851ed2d257b9`. ADB confirmed `IPower/default`, `performance_hint`, `window`, and `activity` registration.
- The earlier minimal-guest `init.rc` patch had skipped `trigger load-bpf-programs`; this left `netd` unstarted while `NetworkManagementService` waited. Restored the standard trigger and canonical patch/audit, then rebuilt only `systemimage` in 22 seconds. New system SHA-256 `48de12b56d2be62ef70843a5d7a5a69d6bbd8c80db9c4a96d46c4fcb1231d16d`; vendor remains `d65616c5...`. In a fresh QEMU run, `NetBpfLoad` completed, `bpf.progs_loaded=1`, and `netd1shot` exited 0. A prior manual ADB invocation of `netbpfload` was invalid because it lacked init's `ANDROID_FILE__dev_kmsg`; it partially populated BPF maps and made a second run fail the empty-map guard. That snapshot was discarded; it is not evidence of kernel incompatibility.
- The genuine next blocker is the 7.3-rc4 kernel configuration: guest `iptables -L OUTPUT -t filter` and `ip6tables` report that the legacy `filter` table does not exist; `netd` then loops with `Failed to initialize iptables rules`, so `sys.boot_completed` remains empty. A delayed full-desktop screenshot after that diagnosis is `qemu-desktop-ui-standard-bpf-netfilter-kernel-blocker-20260925.png`; it is active black output, not the Android UI. Earlier delayed screenshots are `qemu-desktop-ui-rs-jni-systemserver-classpath-blocker-20260925.png` (still not active) and `qemu-desktop-ui-derived-classpath-hintmanager-powerhal-blocker-20260925.png` (active black). UART logs use matching tags under `aosp/windows-arm64-test/`.
- Host 185's `/home/keke/projects/kikiaosp_kernel` was fast-forwarded from its stale clone to remote commit `101444a` (the reproducible 7.3-rc4 flake); the original worktree was clean. The flake now explicitly selects Linux 7.3's split `NETFILTER_XTABLES_LEGACY`, IPv4/IPv6 legacy evaluators, and built-in filter/mangle/raw/NAT tables required by Android's `iptables-legacy`. `git diff --check` and Nix dry-run passed. The rebuild is running in the existing `kiki-hwc-guest:kernel-netfilter` tmux window with proxy `192.168.2.2:6152`; this paragraph does not claim a new kernel or UI result yet.
- Acceptance still requires guest netd/framework boot completion, a genuine Android APK window with a Close button and two distinct visible frames in Windows desktop captures, plus the previously agreed 30-minute stability test. None is claimed at this checkpoint.

### W5-DELAYED-DESKTOP-EVIDENCE-AND-ZYGOTE-LOOP-CORRECTION-20260925
- Correction to the preceding section: visual reinspection of `qemu-desktop-ui-standard-bpf-netfilter-kernel-blocker-20260925.png` and `qemu-desktop-ui-derived-classpath-hintmanager-powerhal-blocker-20260925.png` shows **`Display output is not active`**, not active black output. Their previous labels were erroneous; neither proves a rendered Android frame.
- The 7.3-rc4 Nix kernel build with legacy IPv4/IPv6 netfilter tables completed successfully (`KIKI_KERNEL_EXIT=0`). Kernel SHA-256: `289e12b89f54b143e253e3aaa4411ffc6f681ad5dfbdd2fd73f0e217629d0d45`; the Windows copy matched.
- A fresh Windows QEMU run with that kernel and matching Android partitions passed BPF loading (`bpf.progs_loaded=1`), started `netd`, and entered Framework `StartConnectivityService`. It did **not** boot Android to UI: Zygote was SIGKILLed and restarted repeatedly from roughly 32 seconds, `audioserver` repeatedly SIGSEGV'd with no guest audio HAL registered, and ADB became offline. Serial alone does not prove which event killed Zygote; this was not a whole-guest reboot.
- Only after confirming the repeating state in UART, captured the foreground/maximized 2880x1920 Windows desktop to `C:\Users\keke\Downloads\temp\qemu-desktop-netfilter-zygote-loop-20260925.png`. It still visibly shows **`Display output is not active`**. Closed QEMU PID 7152 afterward and verified ports 4447/5555 were clear.
- Replaced the Kiki-only delayed one-shot logcat diagnostic (which exited 1 without a usable dump) with a continuous error-level main/system/crash log reader directed to serial. The canonical device-repository patch matches the AOSP working tree; integration and device-profile audits passed. Incremental `systemimage` build completed in 24 seconds. Next boot must establish the *first fatal stack* before changing guest HAL/service dependencies.

### W5-SOUNDTRIGGER-AUDIOHAL-ROOTCAUSE-AND-FIX-20260925
- Corrected visual interpretation: the user's “black immediately after maximizing” observation is a window/display transition and is not being treated as Android crash evidence. Guest restart judgments remain based on UART process/init events.
- In the current Battery/Health-HAL run, `android.hardware.health.IHealth/default` is found and `StartJobScheduler` is crossed. The first SystemServer then reaches `StartSoundTrigger`; about five guest seconds later the serial records `Assertion failed: status != NO_ERROR`, followed by zygote/system_server restart. This same sequence recurs once per server cycle.
- Matched the exact fatal assertion to upstream `frameworks/base/services/core/jni/com_android_server_soundtrigger_middleware_ExternalCaptureStateTracker.cpp`: `LOG_ALWAYS_FATAL_IF(status != NO_ERROR)` after `AudioSystem::registerSoundTriggerCaptureStateListener(listener)`. In the same run, init reports the AIDL vendor audio service names are absent, servicemanager cannot find `android.hardware.audio.core.IModule/default` or `android.hardware.audio.effect.IFactory/default`, and `audioserver` repeatedly receives SIGSEGV. This strongly identifies the missing audio service provider as the cause of the listener-registration fatal, not a display resize or a BatteryService regression.
- Targeted product fix: add AOSP's `com.android.hardware.audio` vendor APEX, whose upstream definition packages the example AIDL audio core and effect services, their init rc, and audio VINTF manifest. Keep Android audio/audioserver enabled; do not mask the SoundTrigger path. Update the device-profile audit to require this package. This is a candidate fix pending incremental build and a fresh Windows QEMU/serial validation; no UI success is claimed yet.

### W5-AUDIO-END-TO-END-PLAN-20260925
- The `com.android.hardware.audio` system/vendor image build completed successfully in 8:25; the vendor APEX is present in `out/target/product/kikiaosp_test/vendor/apex/`. This is a build result only. No boot, playback, or UI success is inferred from it.
- Verified the existing Windows ARM64 QEMU binary exposes `virtio-sound-pci` with an `audiodev` property and the `dsound` backend. QEMU's upstream VirtIO Sound documentation specifies `-device virtio-sound-pci,audiodev=...` and requires guest `CONFIG_SND_VIRTIO`. The existing Kiki Linux 7.3-rc4 base config explicitly has `# CONFIG_SND_VIRTIO is not set`, and its Nix overrides do not enable it.
- Verified AOSP's current example AIDL HAL already implements `StreamPrimary` over `StreamAlsaMonoPipe`, defaults to ALSA card 0/device 0, and converts policy XML module `primary` to AIDL `IModule/default`. It switches to a stub driver for unsupported/disconnected devices; policy/device naming must select an actual ALSA-backed speaker route. The current Kiki product has no installed `audio_policy_configuration.xml`, so the audio APEX alone does not constitute a usable primary audio route.
- Proposed first implementation: retain AOSP's upstream example AIDL core/effects APEX; add a minimal Kiki-owned vendor audio policy with one primary stereo PCM playback port and Speaker route (48 kHz, 16-bit initially), plus its required volume/config files. Keep telephony, FM, Bluetooth, offload, MMAP, and microphone routes out of the first profile. Register the audio HAL through the APEX's own init/VINTF declarations, avoiding framework-source edits.
- Add `SND_VIRTIO = yes` to the reproducible `kikiaosp_kernel` Nix configuration on host 185, preserve the tested 4K/netfilter settings, rebuild and verify the output config and guest `/proc/asound/cards`, `/dev/snd/pcmC0D0p`. Add opt-in QEMU args `-audiodev dsound,id=kiki_audio -device virtio-sound-pci,audiodev=kiki_audio,streams=1` to the local Windows runner. Verify card/device numbering instead of assuming it; adjust the Kiki policy address or HAL mapping only if needed.
- The example HAL expects certain ALSA mixer controls for hardware volume. Whether virtio-sound exposes compatible controls is unverified; check `/proc/asound`, mixer enumeration, and logs during the first boot. If playback works but hardware volume calls are unsupported, add a small Kiki-owned adaptation using the existing software gain path instead of editing upstream AOSP or replacing the entire AIDL HAL.
- Acceptance gates: (1) stable `audioserver`, registered `IConfig/default`, `IModule/default`, and effects factory; no SoundTrigger fatal or zygote loop; (2) guest Android `AudioTrack` test emits a known tone, first verifiable via QEMU's WAV backend and then via DirectSound/Windows loopback, and `dumpsys media.audio_flinger` shows an ALSA-backed route rather than a stub; (3) 30-minute boot/playback stability. Native UI debugging may proceed after gate 1 while sound playback is validated; visual UI success still needs its own evidence.
- DirectSound is playback-only in QEMU's upstream documentation. Microphone capture remains a separate phase: test another built Windows backend for capture or implement a Windows-native WASAPI input path in the Kiki QEMU build, then add the guest capture stream, Mic policy route, permission/privacy handling, and round-trip test. Do not advertise recording support in the initial output-only profile.

### W5-UI-FIRST-AUDIO-BYPASS-FONT-TETHERING-20260925
- User clarified the priority: obtain a real Android UI as soon as possible; playback can remain silent, microphone is not needed. Keep `SND_VIRTIO` disabled for now and enable it only alongside a future kernel rebuild needed for the primary UI path, or pursue full audio integration only if the startup audio blocker cannot be bypassed quickly.
- The AOSP audio APEX build succeeded. Windows test `ui-audio-apex-no-policy-20260925` found its effect HAL exits with status 1: upstream `EffectMain.cpp` explicitly exits if `audio_effects_config.xml` is absent. With no `audio_policy_configuration.xml`, the core service also could not create `IModule/default`. Its init `onrestart` chain repeatedly killed `audioserver`. QEMU was stopped after diagnosis.
- Added a Kiki-owned minimal primary Speaker policy, the upstream audio effects and volume files, and a Windows runner switch `-AudioStubOutput` that sets `ro.boot.audio.tinyalsa.ignore_output=true`. The next run registered `IConfig/default` and `IModule/default`, but `audioserver` waited for `IModule/r_submix`. Source audit found the stock audio APEX declares `default`, `r_submix`, and `bluetooth` and `DevicesFactoryHalAidl` enumerates every declared module. Added the two upstream software-module policies together, without introducing audio hardware. The subsequent run registered all three modules plus `IFactory/default`, passed `StartAudioService` and `StartSoundTrigger`, and reached Framework boot phase 480 with no audio restart loop. Kernel unchanged and no real playback claimed.
- A delayed, maximized Windows desktop capture for that run still visibly read `Display output is not active`: `C:\Users\keke\Downloads\temp\qemu-desktop-ui-audio-pass-phase480-20260925.png`. ADB was offline. The old one-shot logcat diagnostic wrote oversized buffers to `/dev/kmsg` and exited with `fwrite failed: Invalid argument`; added a temporary, bounded, per-line log dump to the existing Kiki ADB staging script. The system-only diagnostic rebuild succeeded in 25 seconds, SHA-256 `0aae1bd196b5b283be2e8cb630848e27d34060b1c92a3f7a948691f1898f4abb`.
- That dump exposed the actual phase-480 deadlock: the minimal product omitted `/system/etc/font_fallback.xml` and all system fonts. `FontManagerService_create` failed with a `Typeface` null dereference before completing its startup future; `FontManagerService.onBootPhase(480)` then waited forever. Added only the stock font product fragments used by AOSP `handheld_system.mk`, not its phone/application service graph. The font rebuild succeeded in 3:56 and installed `font_fallback.xml` plus 206 fonts; system SHA-256 `6a8dfb0ec98aa6fa829cb0a7a1a4830df1e1291fa96052b7fb2f0b645fc1c66f`.
- The font-image retest crossed phase 480 and 500, then failed in phase 550 at `NetworkStatsServiceInitializer.systemReady()`: `mContext.getSystemService(TetheringManager.class)` returned null and `registerTetheringEventCallback` threw. The `com.android.tethering` APEX was already installed; inspection showed an old Kiki patch had removed the stock `TetheringManager` registration from `SystemServiceRegistry`. Restored those upstream lines in AOSP and removed the corresponding hunk from the canonical Kiki patch. Added an audit invariant; the full AOSP integration audit passed (170 tracked patch paths, 5 overlays). Its incremental `systemimage` build is running in the existing 185 tmux build window as `build-ui-tethering-registry-20260925.log`. No claim of phase 600, ADB recovery, or UI output yet.
- Second delayed full-desktop capture remained `Display output is not active`: `C:\Users\keke\Downloads\temp\qemu-desktop-ui-font-pass-tethering-registry-blocker-20260925.png`. Each diagnostic QEMU was closed through HMP after evidence collection. Preserve the silent output switch as an opt-in bring-up tool; do not include virtio-sound or rebuild the kernel until a UI-critical reason exists.

### W5-UI-FIRST-PHASE600-FUSED-LOCATION-20260925
- The Tethering registry repair built successfully in 3:47; system image SHA-256 `959a72e67cdd49e6d94ba3d9dd9ab52c6231eaec04825f7acace02b36d835073` was verified after SCP to Windows. Booting it with the unchanged 7.3-rc4 netfilter kernel, audio-module vendor image, and silent `-AudioStubOutput` path passed Framework phases 480, 500, 520, and 550 and reached phase 600. The audio services did not restart; the earlier 550 failure is resolved.
- The next first fatal was `LocationManagerService$Lifecycle.onBootPhase(600)`: `Unable to find a direct boot aware fused location provider`. Source inspection confirmed an unconditional `queryIntentServicesAsUser(ACTION_FUSED_PROVIDER, MATCH_DIRECT_BOOT_AWARE | MATCH_SYSTEM_ONLY)` check. AOSP `handheld_system.mk` installs its own `FusedLocation` privileged APK and includes it in `PRODUCT_SYSTEM_SERVER_APPS`; Kiki's minimal product omitted both. Added only that upstream package, its stock `preinstalled-packages-platform-handheld-system.xml` user-type rule, and the system-server app declaration to the Kiki device product. The integration audit again passed (170 tracked patch paths, 5 overlays); the incremental system image build is running in the existing `kiki-hwc-guest:4.1` tmux pane as `build-ui-fused-location-20260925.log`.
- The phase-600 diagnostic QEMU was closed after the fatal; HMP removed listeners but its GTK process lingered, so PID 24980 was explicitly terminated and no QEMU process remains. The Windows desktop still has no proven Android UI; do not claim otherwise. No microphone, virtio-sound hardware, or kernel configuration changes were made.
- The `FusedLocation` rebuild completed successfully in 4:17 with 120 scheduled actions after a Soong graph refresh; system SHA-256 `e23fc5da5d110a626fde90bd1561ed9b6f323760f0492588badfa071b1cfb983` was verified after transfer. The local run passed all phase-600 callbacks, launched parts of SystemUI, and emitted `sys.boot_completed=1`, but SystemServer soon died in `LockSettingsService.migrateUserToSpWithBoundKeysLocked`: `Could not connect to Keystore service`. A delayed, maximized 2880x1920 Windows screenshot `C:\Users\keke\Downloads\temp\qemu-desktop-ui-fused-location-keystore-fatal-20260925.png` shows an active pure-black QEMU output, **not** an Android window. The QEMU process was terminated after capture.
- Source audit found the legacy AOSP patch deliberately inserted `stop keystore2` into `system/core/rootdir/init.rc` early-init, even though the system still installs `keystore2`. Removed only this stop; retained the current fast-boot keystore module-hash and earlyBootEnded bypass for this UI bring-up. Added AOSP Goldfish's software `android.hardware.security.keymint-service` plus `com.android.hardware.gatekeeper.nonsecure` to the Kiki product. This restores the core Keystore/LockSettings contract without hardware security or phone peripherals; no SELinux or upstream HAL implementation was changed. The canonical patch and actual source agree, and the integration audit passes (170 patch paths, 5 overlays). A combined incremental `systemimage vendorimage` build is running in the existing tmux pane as `build-ui-keystore-software-hals-20260925.log`.
- The combined build completed in 4:45 with 833 executed actions. System SHA-256 `8d7b94b78256a61f843ae606e1a18e9d2210944ef0fc3d25670db01bddc82eb8`; vendor SHA-256 `88b3d7c5191e59abe9234190a94bdbc64040f4ad87243c6ab534969aac44e4c8`; both verified on Windows. The local QEMU run registered Keystore2, KeyMint, SharedSecret, SecureClock, and Gatekeeper, passed boot phase 600 and `sys.boot_completed=1`, but SurfaceFlinger received `SIGSEGV` as UI clients began drawing. SystemUI then crashed/restarted. A delayed, maximized Windows capture `C:\Users\keke\Downloads\temp\qemu-desktop-ui-keystore-hals-after-boot-20260925.png` shows active black output, not an Android UI; QEMU was stopped afterward.
- To avoid guessing at that native display crash, added a temporary delayed `/data/tombstones` dump to the Kiki device boot diagnostic, rebuilt only 6 system actions in 26 seconds, and retested. System SHA-256 `8790d2916188147f1e6817fcc0b0536460fe816f6696952062d22beeffc2cdab`. The crash reproduced at boot-complete and the captured `tombstone_22` identifies thread `RenderEngine`, `SIGSEGV` read `0x0000013d00000010`, frame `AutoBackendTexture::CleanupManager::cleanup()+112`, called from `SkiaRenderEngine::cleanupPostRender()`. The tombstone is preserved in `aosp/windows-arm64-test/qemu-kikiaosp-ui-sf-tombstone-diagnostic-20260925.log` around `KIKI-SF-TOMBSTONE-DUMP-BEGIN`; QEMU was stopped after collection.
- Source analysis found the Kiki CPU-raster fallback in `GaneshBackendTexture::makeSurface()` can synchronously call `releaseSurfaceProc` when AHardwareBuffer locking or WrapPixels fails, while stock `AutoBackendTexture::getOrCreateSurface()` increments its use count only *after* `makeSurface()` returns. That can queue the same texture twice and make cleanup dereference a freed backend pointer. Moved the `ref()` before calling `makeSurface()` in the AOSP working tree and the canonical Kiki patch; integration audit passes with 171 tracked patch paths and 5 overlays. An incremental `systemimage` rebuild is running as `build-ui-sf-texture-lifetime-20260925.log`. This is a targeted lifetime fix, not proof of visible UI; retest the output and crash count next.
- That targeted rebuild completed in 1:23 with 14 actions, system SHA-256 `4bf461698b60e763d4704b7cf0b06f7e31d5fa033c1ffafe71b6d1955e3e7e70`, verified on Windows. The guest again reached `sys.boot_completed=1`, and SurfaceFlinger no longer recorded the cleanup SIGSEGV during the observed run. A maximized Windows capture `C:\Users\keke\Downloads\temp\qemu-desktop-ui-sf-texture-lifetime-boot-20260925.png` still showed active pure black, not a real Android window.
- With the native compositor surviving, the next first UI blocker is the SystemUI RenderThread abort in `EglManager::damageFrame()`: `eglSetDamageRegionKHR` fails `EGL_BAD_ACCESS`. AOSP HWUI reads device properties `debug.hwui.use_buffer_age` and `debug.hwui.use_partial_updates`; the failure path is entered only with `SwapBehavior::BufferAge`. Set both properties to `false` in the Kiki product to request a full-frame swap, leaving generic HWUI source untouched. The integration audit passes (171 patch paths, 5 overlays), and an incremental system image build is running as `build-ui-hwui-full-frame-20260925.log` in the existing tmux build pane. The preceding diagnostic QEMU was closed after evidence collection; no UI success is claimed.

### W5-ACTUAL-ANDROID-APK-UI-KEEP-AWAKE-GTK-FULL-REDRAW-20260926
- User reaffirmed that visible Android UI is the sole priority; microphone and playback are not required. Keep the already-tested silent audio bypass (`-AudioStubOutput`, `androidboot.audio.tinyalsa.ignore_output=true`); do not add `CONFIG_SND_VIRTIO` or change the rc4 kernel for this UI path.
- Root cause for the delayed black screen: after the Activity had been displayed and animated guest frames were reaching QEMU, Linux entered `PM: suspend entry (s2idle)` at guest uptime 133.876s and the guest issued `SET_SCANOUT res=0`, returning QEMU to its inactive-display placeholder. The test Activity did not hold the display awake.
- Added `WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON` to KikiWindowTest. Incremental `m KikiWindowTest` succeeded in 13s (10 Ninja actions); `m systemimage` then succeeded in 25s (4 Ninja actions). No vendor image, system service graph, audio configuration, or kernel rebuild was needed. New Windows system image SHA-256: `9c51376df8e0534bb00f6021fc754fbc614f66e90e991f4fdd233498611b763a`.
- Retest with the unchanged Linux 7.3-rc4 4K/netfilter kernel and existing vendor image showed `Displayed com.kikiaosp.windowtest/.MainActivity` at guest uptime 80.506s. The guest remained awake with changing scanout pixels through at least 278.619s; no subsequent `PM: suspend entry` was present. A QEMU monitor screendump contained the full `TEST OK` Android Activity.
- Separate Windows GTK issue: QEMU's GTK/Cairo source image and monitor dump contained the complete Activity, but ordinary dirty-rectangle updates intermittently left only the moving square visible in the native window. A temporary environment-gated redraw hook was tried. Correction after inspecting the actual files: the earlier `...full-redraw-frame1...` capture showed the complete Activity, but `...full-redraw-frame2...` contained only the black field and moving square. That pair is invalid as two-frame UI evidence; do not rely on the earlier two-frame claim.
- The earlier run established neither repeated full-UI Windows frames nor a 30-minute stability claim. See the following verification entry for corrected evidence. Audio and microphone integration remain deferred unless a future UI-critical kernel rebuild gives a convenient opportunity to add the option.

### W5-ACTUAL-ANDROID-APK-UI-WINDOWS-GTK-REPAINT-VERIFICATION-20260926
- Kept the Android and rc4 kernel images unchanged. The Android 17 `system-kikiaosp-ui-keep-screen-on-20260926.img` remained paired with the existing vendor image and `kernel-linux-7.3-rc4-4k-netfilter-20260925`; QEMU used the existing silent `-AudioStubOutput` argument. No microphone, virtio-sound, audio kernel option, Android rebuild, or kernel rebuild was introduced.
- Reproduced the native GTK partial-damage issue and changed QEMU `ui/gtk.c` to repaint the full drawing area on Windows (`G_OS_WIN32`) when guest damage arrives. The final Windows-targeted QEMU build succeeded (`ninja -C tools/qemu-src/build qemu-system-aarch64.exe`, 3 build actions); Linux GTK's normal dirty-rectangle path is unchanged.
- The guest reached `sys.boot_completed=1` at about 63s uptime. UART subsequently recorded recurring successful Kiki client-target setup and `WINQ-PRESENT flush` events; the guest stayed active through at least 238s uptime. ADB reported its transport offline during this particular run; ADB availability is not inferred from the visual test.
- Captured and visually inspected two full Windows desktop frames at 2880x1920 using `tools/capture_qemu_window.ps1`, 20 seconds apart. Both show the QEMU window with the native `KikiAOSP test window` Android Activity, Close button, `TEST OK`, and subtitle. The animated square is in different positions, demonstrating distinct rendered frames:
  - `C:\Users\keke\Downloads\temp\qemu-desktop-ui-unconditional-full-redraw-frame1-20260926.png` — SHA-256 `6b0ee6f32e67ac1ac1cbae116c7ccb02be3733862cc09e2069e586a98de699d5`.
  - `C:\Users\keke\Downloads\temp\qemu-desktop-ui-unconditional-full-redraw-frame2-20260926.png` — SHA-256 `921f41363fa3e7c5e8aa5a3c55c943ecce397776985ffc9b3f3e46d2217c1693`.
- This is positive evidence that the APK's Android Activity is visible in the actual Windows QEMU window across multiple frames. It is not a 30-minute soak or a claim that ADB was online. QEMU PID 24260 was stopped after capture; no listeners remained on ports 4447/5555.
