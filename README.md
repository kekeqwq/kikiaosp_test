# KikiAOSP Test

KikiAOSP is a native ARM64 Android 17 test target for Windows ARM hosts. It is a kernel/Android boot and graphics test environment, not a phone product.

## Verified baseline and active target

- Device: `kikiaosp_test`
- Product: `kikiaosp_test_arm64_phone`
- System identity: `KikiAOSP`
- AOSP baseline: Android 17 development `master` manifest
- Kernel: Linux `v7.3-rc4`, 4 KiB pages, from https://github.com/kekeqwq/kikiaosp_kernel
- Emulator: upstream QEMU `aarch64-softmmu`, machine `virt`, `virtio-gpu-pci`
- Android graphics: ranchu HWC3/minigbm and SurfaceFlinger client composition

The released black-screen image is a historical reference checkpoint, not the active UI product. It intentionally has no Launcher or Android app window. Its SurfaceFlinger/HWC/DRM startup and black scanout were verified separately; that does not prove Android WindowManager or an APK is rendering.

The current device-tree work now composes AOSP's generic core with a deliberately small native UI set (`Launcher3QuickStep`, `Settings`, `SystemUI`, `LatinIME`, and the `KikiWindowTest` APK). The product selects the full Framework startup branch rather than the earlier boot-only/minimal-service mode, and Kiki init no longer stops Android native services. Some Kiki-specific Framework conditionals remain in the tracked AOSP patch set and still require a boot audit. This source configuration has not yet been rebuilt or boot-validated: the Android UI, Close button, two animated APK frames, and a 30-minute run remain unproven acceptance gates.

The minimal Ranchu init hook calls `mount_all /vendor/etc/fstab.ranchu` during `fs` and `late-fs`; keep both files under `vendor/etc` so `/data` and the remaining test partitions are mounted. `/data` is a `latemount` entry because Android mounts it during late-fs after core properties are available.

## Repository layout

```
device/kiki/kikiaosp_test/       device/product definition
patches/aosp-working-tree.patch  tracked AOSP source changes
patches/aosp-render-output.patch raster client-target bring-up changes
patches/archive/                    superseded patch drafts, not applied
overlays/                        required formerly-untracked source files
scripts/apply-aosp-integration.sh
scripts/sync-device-tree.sh
```

The upstream AOSP checkout is never committed here. Apply this tree and patch set explicitly to a clean checkout.

The active patch set is file-disjoint and each patch is reverse-dry-run checked
by `scripts/audit-aosp-integration.sh`. The former `aosp-hwc-dmabuf-map.patch`
was an overlapping intermediate edit to `GuestFrameComposer.cpp`; its final
combined source state is carried by `aosp-hwc-device-buffer-map.patch`, so the
intermediate is archived and is not applied.

## 1. Prepare a Linux build host

Arch example (use equivalent packages on Debian/Ubuntu):

```bash
sudo pacman -Syu
sudo pacman -S --needed git curl python unzip zip rsync bc bison flex gcc clang lld make ninja cmake cpio lz4 pigz openssl libelf libxml2 ncurses readline zlib perl schedtool fontconfig freetype repo
mkdir -p ~/projects
git clone https://github.com/kekeqwq/kikiaosp_kernel.git ~/projects/kikiaosp_kernel
git clone https://github.com/kekeqwq/kikiaosp_test.git ~/projects/kikiaosp_test
```

Use at least 32 GiB RAM and about 250 GiB free disk. Run long builds in `tmux`.

## 2. Fetch original AOSP

```bash
mkdir -p ~/aosp-master
cd ~/aosp-master
repo init -u https://android.googlesource.com/platform/manifest \
  -b master --partial-clone --clone-filter=blob:limit=10M
repo sync -c -j"$(nproc)" --fail-fast
test -f .repo/manifest.xml
repo list | wc -l
```

Sync is incremental. The development proxy used previously was:

```bash
export HTTP_PROXY=http://192.168.2.2:6152
export HTTPS_PROXY=http://192.168.2.2:6152
repo sync -c -j8
```

## 3. Apply Kiki integration

```bash
cd ~/projects/kikiaosp_test
./scripts/apply-aosp-integration.sh ~/aosp-master
cd ~/aosp-master
repo status
```

The script synchronizes `device/kiki/kikiaosp_test` without deleting unknown files in the AOSP destination, applies the graphics/runtime patch set, and copies the overlays. Use a fresh checkout for a reproducible upstream baseline; to return to pure upstream, restore it from version control. Do not commit Kiki changes into upstream AOSP.

After editing files under `device/kiki/kikiaosp_test/` in this repository,
sync that device tree into the separate AOSP working tree before building:

```bash
cd ~/projects/kikiaosp_test
scripts/sync-device-tree.sh ~/aosp-master
```

This copies the repository's device tree without touching the rest of AOSP.

## 4. Build Android

```bash
cd ~/aosp-master
source build/envsetup.sh
lunch kikiaosp_test_arm64_phone-trunk_staging-userdebug
tmux new -s kikiaosp-build
m -j"$(nproc)" systemimage
```

Detach with `Ctrl-b d`; reattach with `tmux a -t kikiaosp-build`. Reuse the same `out/` directory for incremental builds. Main output is `out/target/product/kikiaosp_test/` containing `system.img`, `vendor.img`, `product.img`, `system_ext.img`, `odm.img`, and vendor-boot/ramdisk outputs.

## 5. Build the prepared kernel

```bash
cd ~/projects/kikiaosp_kernel
nix build
mkdir -p ~/kiki-artifacts
cp -L result/boot/kernel ~/kiki-artifacts/kernel-linux-7.3-rc4-4k
```

The flake emits `result/boot/kernel`, `result/boot/vmlinux`, `result/boot/config`, and `result/modules/`. The verified rc4 source is `kikiaosp_kernel` commit `101444a3717c1f1251d586572975853ad1bf3aea`. Check `result/boot/config` and `uname -r` after boot before replacing the frozen test artifact.

## 6. Assemble test assets

QEMU needs a kernel, Android vendor ramdisk, system image, userdata image, and `misc.img`. Optional product/system_ext/vendor/odm images can be attached as additional virtio disks.

The verified reference layout is:

```
kiki-artifacts/
  kernel-linux-7.3-rc4-4k
  kiki-kernel-ramdisk.img
  kiki-kernel-system-black-adb.img
  userdata-qemu-fresh.img
  misc.img
```

`kiki-kernel-system-black-adb.img` is made by `scripts/repack-black-baseline.sh` from the frozen `kiki-kernel-system.img` EROFS tree. The repack adds the tracked TCP-only `adbd`, a static DRM black-frame helper, and the `kikiaosp_test` product identity. A plain `m systemimage` output is not yet equivalent to this frozen flat-image baseline.

Download the frozen base image and ramdisk from the repository's
`black-baseline-2026-09-23` GitHub release, then verify the base hash shown in
section 11. A fresh 8 GiB sparse `userdata-qemu-fresh.img` and 4 MiB `misc.img`
can be created with `qemu-img create -f raw`; the QEMU command uses `-snapshot`
so tests do not persist writes to these files.

```bash
gh release download black-baseline-2026-09-23 \
  --repo kekeqwq/kikiaosp_test --dir ~/kiki-artifacts
sha256sum ~/kiki-artifacts/kiki-kernel-system.img \
  ~/kiki-artifacts/kiki-kernel-ramdisk.img
```

## 7. Build upstream QEMU with MSYS2

Use the **MSYS2 UCRT64** terminal, not the plain MSYS shell:

```bash
pacman -Syu
# restart UCRT64 after the first upgrade
pacman -Su
pacman -S --needed git make diffutils patch perl python pkgconf ninja \
  mingw-w64-ucrt-x86_64-toolchain \
  mingw-w64-ucrt-x86_64-glib2 mingw-w64-ucrt-x86_64-gtk3 \
  mingw-w64-ucrt-x86_64-SDL2 mingw-w64-ucrt-x86_64-libslirp \
  mingw-w64-ucrt-x86_64-zstd mingw-w64-ucrt-x86_64-libusb

cd ~/projects
git clone https://gitlab.com/qemu-project/qemu.git qemu
cd qemu
git submodule update --init --recursive
./configure --target-list=aarch64-softmmu --enable-whpx --enable-gtk --disable-werror
make -j"$(nproc)"
./build/qemu-system-aarch64.exe --version
```

If GTK is unavailable, use `--disable-gtk --enable-sdl` for a functionality build. The tested graphical mode is `-display gtk,gl=off`; no Habumi fork is used. On Windows ARM, `-accel whpx` uses Hyper-V; fallback is `-accel tcg,thread=multi`.

## 8. Start the test system on Windows

```powershell
$qemu = "C:\path\to\qemu\build\qemu-system-aarch64.exe"
$d = "C:\path\to\kiki-artifacts"
$append = "earlycon=pl011,0x09000000 console=ttyAMA0 loglevel=8 printk.devkmsg=on audit=0 androidboot.hardware=ranchu androidboot.hardwareegl=angle androidboot.hardware.egl=angle androidboot.hardware.gralloc=minigbm androidboot.hardware.hwcomposer=ranchu androidboot.hardware.vulkan=pastel androidboot.hardware.hwcomposer.mode=client androidboot.hardware.hwcomposer.display_finder_mode=drm androidboot.hardware.guest_hwui_renderer=gles androidboot.debug.renderengine.backend=skiaglthreaded androidboot.selinux=permissive enforcing=0 androidboot.force_normal_boot=1 androidboot.verifiedbootstate=orange androidboot.init_fatal_reboot_target=none binder.devices=binder,hwbinder,vndbinder"

& $qemu -M virt -accel whpx -cpu host -m 4096 -smp 4 `
  -kernel "$d\kernel-linux-7.3-rc4-4k" -initrd "$d\kiki-kernel-ramdisk.img" `
  -append $append `
  -drive "if=none,file=$d\kiki-kernel-system-black-adb.img,format=raw,readonly=on,id=system" -device virtio-blk-pci,drive=system `
  -drive "if=none,file=$d\userdata-qemu-fresh.img,format=raw,id=userdata" -device virtio-blk-pci,drive=userdata `
  -drive "if=none,file=$d\misc.img,format=raw,id=misc" -device virtio-blk-pci,drive=misc `
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:5555-:5555 -device virtio-net-pci,netdev=net0 `
  -device virtio-gpu-pci,hostmem=256M,xres=1080,yres=2400 -display gtk,gl=off `
  -serial "file:$d\qemu-kikiaosp.log" -snapshot
```

Watch serial output with `Get-Content "$d\qemu-kikiaosp.log" -Wait`. The graphics checkpoint is:

```
WINQ-SF primary connected=1
WINQ-SF: after flinger init
```

Stop every test:

```powershell
Get-Process qemu-system-aarch64 -ErrorAction SilentlyContinue | Stop-Process -Force
```

Linux TCG uses the same devices, replacing `-accel whpx -cpu host` with `-accel tcg,thread=multi -cpu cortex-a53`.

## 9. Proven state and next step

The frozen black baseline previously passed a 1800-second no-panic/no-SIGSEGV/no-core-service-restart run, with ARM64 kernel boot, Android init/Binder/servicemanager/allocator/HWC/SurfaceFlinger startup, DRM connector detection, and ADB. Separately, the native test client submitted two solid-color SurfaceComposer layers (background and moving square); QEMU monitor captures proved two distinct frames from the actual display output. That is display-pipeline evidence, not evidence of an Android Activity window.

This proves the minimal Android layer → SurfaceFlinger → GuestFrameComposer → DRM/KMS → QEMU display path for solid-color layers. It does not yet prove arbitrary app-buffer/client-target composition, a launcher/window manager, input, sustained stability, or high-refresh operation. The current acceptance target is the visible animated `KikiWindowTest` Android Activity with a usable Close button and at least two distinct Windows desktop frames. See [the two-frame rendering checkpoint](#12-native-two-frame-ui-proof-2026-09-23) for the earlier native-layer evidence and hashes.

## 10. Development history

Work in this repository or `kikiaosp_kernel`, not by committing Kiki changes into upstream AOSP:

```bash
git checkout -b feature/<name>
git add .
git commit -m "<scope>: <change>"
git push -u origin feature/<name>
```

Every reproducible checkpoint records the AOSP manifest revision, kernel commit, image SHA-256, QEMU arguments, serial conclusion, and known limitations in `Work_5day.md`.

Before any build, run the integration audit from the device repository:

```bash
./scripts/audit-aosp-integration.sh ~/aosp-master
./scripts/audit-device-tree-profile.sh
```

The audit verifies that every AOSP modification is represented by this repository's patch/overlay set and that the selected product is the fixed `userdebug` target. It fails closed if an unrelated AOSP change or an `eng`/other product configuration is present, preventing an accidental configuration switch and installclean.

## 11. Repack the active black baseline

The frozen base image is published as a release asset and has SHA-256
`ad60b844b0a23c835aaf129f548b0fff03f1bf01588cb6645c9b3a0f0f6b20d7`.
Keep `kiki-kernel-system.img` and `kiki-kernel-ramdisk.img` from the verified
asset set. The independent repository contains the source and repack recipe;
the 491 MB base image is hosted as a release asset rather than Git history.

With `erofs-utils` and an ARM64 Linux cross compiler available on the Linux
build host, run:

```bash
cd ~/projects/kikiaosp_test
scripts/repack-black-baseline.sh \
  ~/kiki-artifacts/kiki-kernel-system.img \
  ~/aosp-master \
  ~/kiki-artifacts/kiki-kernel-system-black-adb.img
```

Set `CROSS_CC=/path/to/aarch64-unknown-linux-gnu-gcc` if the compiler is not
on `PATH`. The script extracts the EROFS base, installs the tracked ADB and DRM
sources, copies `adbd_flags_c_lib.so` from the matching AOSP build, fixes the
old image's `vsoc_arm64` product property, checks the repacked filesystem, and
prints its SHA-256. The tested output hash is
`c0c7f7f3737052dd4f53f8d3892d0278aa4cb2f0f32ec12f07a3aebde2054cc7`.
Two independent repacks produced byte-identical images with this hash.

On Windows, `scripts/run-black-baseline.ps1 -Qemu <qemu-system-aarch64.exe>
-Assets <kiki-artifacts>` launches the exact tested device order and QEMU
options. The window remains open until you close QEMU. After `adb connect
127.0.0.1:5555`, verify `adb shell getprop ro.product.device` returns
`kikiaosp_test`. The serial log must contain `KIKI-BLACK scanout active`.

## 12. Native animated `TEST OK` UI proof (2026-09-23)

The minimal visible UI now renders readable `TEST OK` text and an animated
square using only native SurfaceComposer solid-color effect layers. The text is
a 5×7 bitmap font represented by 53 horizontal color strokes; the composition
also has one dark background and one moving square. The square changes position
and color every 500 ms. No Launcher, Android app UI framework, or new system
service was added; the existing opt-in `kiki_test_ui` init service is used.

The upstream AOSP tree and this repository are separate working directories.
After changing the device tree, sync it before compiling so Soong does not
silently reuse an older AOSP-side copy:

```bash
cd ~/projects/kikiaosp_test
scripts/sync-device-tree.sh ~/aosp-master
cd ~/aosp-master
source build/envsetup.sh
lunch kikiaosp_test_arm64_phone-trunk_staging-userdebug
m kiki_test_ui
cd ~/projects/kikiaosp_test
scripts/repack-black-baseline.sh \
  ~/kiki-kernel-system-black-adb.img \
  ~/aosp-master \
  ~/kiki-kernel-system-sf-guest-hwc3-map-ui-test-ok.img surface-test
```

The frozen image uses the active non-APEX Ranchu composer at
`/system/bin/hwcomposer`; the guest minigbm mapper's CPU lock returns `-38`
(`ENOSYS`), so the opt-in HWC path maps the synchronized composer dma-buf and
submits it through the existing DRM flush path. Keep `mode=guest` opt-in; the
frozen black-baseline boot remains unchanged.

The tested image SHA-256 is
`bfe1c79716c623f684cb7376f9791c5df63ffa08545f0303fcb9c6e08d166f38`.
Windows QEMU used upstream `qemu-system-aarch64`, WHPX, `virtio-gpu-pci`
640×480, GTK `gl=off`, and `androidboot.hardware.hwcomposer.mode=guest`.
Evidence PNGs are saved in `docs/evidence/`:

| Evidence PNG | PNG SHA-256 | Source QEMU PPM SHA-256 | Visible result |
| --- | --- | --- | --- |
| `kiki-native-test-ok-frame-1.png` | `78a9be76cd1655c1ea7dc116b920a6109cb9065276c908ac2ad93e36fcc33979` | `678406519929349d192b7e7fd9eaacf978f6b70640ccb2cbbf36bd4a63d99060` | `TEST OK`, square at one position/color |
| `kiki-native-test-ok-frame-2.png` | `4aaaf0fde4d3e0db58ccd834adcae4d9823ab12a5ca4951c657ff459dfd98158` | `a4df9098b298373cf4c9f3f7202c1a1d62c15f51743586c3c30a8f5dbfeea128` | `TEST OK`, square moved and changed color |

Both captures are direct QEMU monitor screendumps of Android's displayed
output. Four consecutive follow-up captures showed the text and background;
one earlier sample immediately after the first successful frame showed only
the square, so this is proof of animated rendering—not yet a long-duration
stability or high-refresh result. At the last check, the guest serial log had
recorded 1,210 successful animation transactions through 658 guest seconds and
QEMU was still running. The broader path is now proven for native solid-color
layers; ordinary app-buffer/client-target composition, input, and high-refresh
behavior remain future work.
