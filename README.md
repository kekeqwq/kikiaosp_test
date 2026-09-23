# KikiAOSP Test

KikiAOSP is a native ARM64 Android 17 test target for Windows ARM hosts. It is a kernel/Android boot and graphics test environment, not a phone product.

## Frozen baseline

- Device: `kikiaosp_test`
- Product: `kikiaosp_test_arm64_phone`
- System identity: `KikiAOSP`
- AOSP baseline: Android 17 development `master` manifest
- Kernel: Linux `v7.3-rc4`, 4 KiB pages, from https://github.com/kekeqwq/kikiaosp_kernel
- Emulator: upstream QEMU `aarch64-softmmu`, machine `virt`, `virtio-gpu-pci`
- Android graphics: ranchu HWC3/minigbm and SurfaceFlinger client composition

The frozen reference image intentionally has no Launcher, bootanimation, or UI layer. SurfaceFlinger reaches `primary connected=1` and `after flinger init`. The active black frame is established by the tracked `kiki_black_scanout` DRM service; compositor startup alone does not make QEMU's display active.

## Repository layout

```
device/kiki/kikiaosp_test/       device/product definition
patches/aosp-working-tree.patch  tracked AOSP source changes
overlays/                        required formerly-untracked source files
scripts/apply-aosp-integration.sh
```

The upstream AOSP checkout is never committed here. Apply this tree and patch set explicitly to a clean checkout.

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

The script installs `device/kiki/kikiaosp_test`, applies the graphics/runtime patch set, and copies the overlays. To return to pure upstream, use a fresh checkout or restore it from version control; do not commit these changes upstream.

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
git submodule update --init --recursive
nix build
mkdir -p ~/kiki-artifacts
cp -L result/boot/kernel ~/kiki-artifacts/kernel-linux-7.3-rc4-4k
```

The flake emits `result/boot/kernel`, `result/boot/vmlinux`, `result/boot/config`, and `result/modules/`. Select the repository revision that builds the verified rc4 4 KiB kernel; check `result/boot/config` and `uname -r` after boot before replacing the frozen test artifact.

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

Proven: ARM64 kernel boot; Android init/Binder/servicemanager/allocator/HWC/SurfaceFlinger startup; DRM connector detection; 1800-second no-panic/no-SIGSEGV/no-core-service-restart run; real SurfaceFlinger client composition without synthetic green frames.

Not yet claimed: a visible Android UI or a finished real-layer scanout path. The current minimal baseline commits one black DRM framebuffer, removes QEMU's `Display output is not active` placeholder, and keeps ADB online with `ro.product.device=kikiaosp_test`. The black frame is a temporary product bootstrap service; it drops DRM master after modeset so a future SurfaceFlinger client target can take over. The next controlled step is to inspect SurfaceFlinger through ADB and submit a real Android layer.

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
