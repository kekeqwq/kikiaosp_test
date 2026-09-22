# KikiAOSP Test

KikiAOSP is a native ARM64 Android 17 test target for Windows ARM hosts. It is a kernel/Android boot and graphics test environment, not a phone product.

## Frozen baseline

- Device: `kikiaosp_test`
- Product: `kikiaosp_test_arm64_phone`
- System identity: `KikiAOSP`
- AOSP baseline: Android 17 development `master` manifest
- Kernel: Linux `v7.3-rc3`, 4 KiB pages, from https://github.com/kekeqwq/kikiaosp_kernel
- Emulator: upstream QEMU `aarch64-softmmu`, machine `virt`, `virtio-gpu-pci`
- Android graphics: ranchu HWC3/minigbm and SurfaceFlinger client composition

The frozen reference image intentionally has no Launcher, bootanimation, or UI layer. SurfaceFlinger reaches `primary connected=1` and `after flinger init`; the stable black result therefore means graphics services initialized with no content, not a finished Android desktop.

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
lunch kikiaosp_test_arm64_phone-trunk_staging-eng
tmux new -s kikiaosp-build
m -j"$(nproc)"
```

Detach with `Ctrl-b d`; reattach with `tmux a -t kikiaosp-build`. Reuse the same `out/` directory for incremental builds. Main output is `out/target/product/kikiaosp_test/` containing `system.img`, `vendor.img`, `product.img`, `system_ext.img`, `odm.img`, and vendor-boot/ramdisk outputs.

## 5. Build the prepared kernel

```bash
cd ~/projects/kikiaosp_kernel
git submodule update --init --recursive
nix build
mkdir -p ~/kiki-artifacts
cp -L result/boot/kernel ~/kiki-artifacts/kernel-linux-7.3-rc3-4k
```

The flake emits `result/boot/kernel`, `result/boot/vmlinux`, `result/boot/config`, and `result/modules/`. The current flake uses a source submodule; on the next kernel upgrade it should be converted to a fixed-hash Nix tarball/fetcher.

## 6. Assemble test assets

QEMU needs a kernel, Android vendor ramdisk, system image, userdata image, and `misc.img`. Optional product/system_ext/vendor/odm images can be attached as additional virtio disks.

The verified reference layout is:

```
kiki-artifacts/
  kernel-linux-7.3-rc3-4k
  kiki-kernel-ramdisk.img
  kiki-kernel-system.img
  userdata-qemu-fresh.img
  misc.img
```

`kiki-kernel-system.img` is the deliberately minimal black-frame image used for the 1800-second stability test. A normal Cuttlefish `system.img` is not equivalent until this product policy and patch set are applied and the image is repacked.

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

Get-Process qemu-system-aarch64 -ErrorAction SilentlyContinue | Stop-Process -Force
& $qemu -M virt -accel whpx -cpu host -m 4096 -smp 4 `
  -kernel "$d\kernel-linux-7.3-rc3-4k" -initrd "$d\kiki-kernel-ramdisk.img" `
  -append $append `
  -drive "if=none,file=$d\kiki-kernel-system.img,format=raw,readonly=on,id=system" -device virtio-blk-pci,drive=system `
  -drive "if=none,file=$d\userdata-qemu-fresh.img,format=raw,id=userdata" -device virtio-blk-pci,drive=userdata `
  -drive "if=none,file=$d\misc.img,format=raw,id=misc" -device virtio-blk-pci,drive=misc `
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

Not yet claimed: a visible Android UI, a finished real-layer scanout path, or ADB access. The next controlled step is to enable `adbd`, run `adb shell getprop`, `ps`, and `dumpsys SurfaceFlinger`, then submit one minimal test Surface. Only if that Surface fails should scanout/present be changed.

## 10. Development history

Work in this repository or `kikiaosp_kernel`, not by committing Kiki changes into upstream AOSP:

```bash
git checkout -b feature/<name>
git add .
git commit -m "<scope>: <change>"
git push -u origin feature/<name>
```

Every reproducible checkpoint records the AOSP manifest revision, kernel commit, image SHA-256, QEMU arguments, serial conclusion, and known limitations in `Work_5day.md`.

