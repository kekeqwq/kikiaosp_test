# KikiAOSP Test

面向 Windows ARM64 QEMU/WHPX 的 Android 17 测试设备。设备身份 `kikiaosp_test`，系统身份 `KikiAOSP`，产品目标 **`kikiaosp_test_arm64_phone-cp2a-userdebug`**；不是 Cuttlefish 手机产品。

本仓库只负责 AOSP 设备树、集成补丁、精确 manifest、审计和镜像构建。[kikiaosp_kernel](https://github.com/kekeqwq/kikiaosp_kernel) 负责内核；[KikiEmu](https://github.com/kekeqwq/KikiEmu) 负责 Windows ARM64 QEMU/相机桥接的源码构建、收集校验、打包及本地测试。Linux 开发机不承担最终 QEMU 测试。

## 当前已验收主线 — 2026-09-30

- AOSP `android17-release`、CP2A release config，Linux 7.3-rc4/4 KiB，Windows ARM/WHPX、SDL 原生窗口、VirGL GPU 显示与合成。
- Launcher3QuickStep、Settings、SystemUI、输入法、三键导航/多任务/通知栏、ADB、Ethernet、扬声器/点按音/铃声试听。系统启动完成，不再预装或自动运行测试桌面/测试窗口。
- DocumentsUI、Gallery2、Camera2、完整 ThemePicker。Surface 前后真实摄像头可切换、正向预览和拍 JPEG，关闭相机释放宿主设备。
- ThemePicker 替换只含壁纸的 WallpaperPicker2；`theme-resources/` 提供六组颜色，设备 overlay 将主题图标接口指向 Launcher3 现有 grid-control provider，上游 required 权限 XML 随模块安装。不修改上游 Launcher3/ThemePicker 源码。
- 当前窗口原生像素 1003×1556、288 dpi、字体缩放 1.5、客体 120 Hz、8 vCPU/4 GiB、无 Grab/console。GPU 加速已经实际验证；此前动画 APK 回调稳定超过 60 FPS，但日常交互仍有延迟，不等于宿主面板 FPS 或完全跟手。

新 system SHA-256 `67f9e0e189efe7e5d6e5e5575a170b269f8862960de38b63292ddea47289ead4`，1,109,270,528 字节；vendor `72202a6af84fc79fc35cefb6d0f6e502fc266b2bbc6c867a49271f4dd234bb4a`，101,437,440 字节。内核 `02c5439434feb3f1b5f5d63f82b2d3fbd6ccb8aa81f93d708f3d0f3bba9a7ce8`。完整启动清单是 KikiEmu 的 `profiles/surface-main-20260930.json`，旧 SHA 仅为历史记录。

相机预览采用 VirGL，采集/传输/转换/JPEG 仍有 CPU 工作；未宣称零拷贝、硬件 JPEG 或视频录制已验收。设备实现见 [camera/README.md](device/kiki/kikiaosp_test/camera/README.md)，实测过程见 [Work_5day.md](Work_5day.md)。

## 从新的 Linux 开发机开始

完整构建建议至少 48 GiB 内存并配 swap，预留 350 GiB 以上磁盘；低内存可减少并发慢跑。Arch 示例：

```bash
sudo pacman -Syu
sudo pacman -S --needed git curl python unzip zip rsync bc bison flex gcc clang lld make ninja cmake cpio lz4 pigz openssl libelf libxml2 ncurses readline zlib perl schedtool fontconfig freetype repo tmux
mkdir -p ~/projects ~/aosp-master
git clone https://github.com/kekeqwq/kikiaosp_test.git ~/projects/kikiaosp_test
git clone https://github.com/kekeqwq/kikiaosp_kernel.git ~/projects/kikiaosp_kernel
cd ~/aosp-master
repo init -u https://android.googlesource.com/platform/manifest -b android17-release --partial-clone --clone-filter=blob:limit=10M
cp ~/projects/kikiaosp_test/manifests/aosp-verified-20260926.xml .repo/manifests/kikiaosp-verified.xml
repo init -m kikiaosp-verified.xml
repo sync -c -j8 --fail-fast
```

`manifests/aosp-verified-20260926.xml` 固定项目提交；浮动 `android17-release` 的新提交不是同一回溯基线。升级上游另开分支重测。网络需要时设置自己的 HTTP_PROXY/HTTPS_PROXY，例如本实验网络 `http://192.168.2.2:6152`；代理是环境配置，不是产品依赖。

## 应用、同步和审计

所有设备改动先在本仓库维护，再同步到 AOSP；不把本地修改提交到上游项目。

首次干净 AOSP：

```bash
cd ~/projects/kikiaosp_test
scripts/apply-aosp-integration.sh ~/aosp-master
scripts/audit-device-tree-profile.sh
scripts/audit-aosp-integration.sh ~/aosp-master
```

后续仅更新设备树：

```bash
scripts/sync-device-tree.sh ~/aosp-master
scripts/audit-device-tree-profile.sh
scripts/audit-aosp-integration.sh ~/aosp-master
```

完整应用入口是 `scripts/apply-aosp-integration.sh`，不是单个大 patch。它应用：

- `patches/aosp-working-tree.patch`：已有核心启动/图形/输入/音频等修改。
- `patches/aosp-kikiaosp-retain-gallery2.patch`：保留 Gallery2。
- `device/kiki/kikiaosp_test/camera/aosp-kikiaosp-camera-sources.patch`：Camera HAL 源码 filegroup 集成。
- `patches/aosp-kikiaosp-settings-kernel-version.patch`：Settings 内核版本读取。
- `patches/aosp-kikiaosp-virgl-context-before-prime.patch`：先初始化 VirGL context 再 PRIME import。
- `patches/aosp-kikiaosp-virgl-cpu-camera-yuv.patch`：CPU 相机 YUV 缓冲分配。
- `overlays/`：上游树少量新增文件；设备内的 `overlay/` 则由产品静态资源叠加机制处理。

不要对已修改工作树盲目重复完整 patch。审计验证所有上游 tracked 修改恰好落在正式 patch 集合中，并反向检查内容；本次通过 183 个 tracked path 和 5 个 overlay path。未纳入正式入口的历史诊断 patch 不应追加。更新集成补丁后再次审计，不靠反复碰错来补依赖。

## CP2A 增量构建

```bash
cd ~/aosp-master
source build/envsetup.sh
lunch kikiaosp_test_arm64_phone-cp2a-userdebug
tmux new -s kikiaosp-build
m -j8 systemimage vendorimage
# 根据内存调整 -j；保留 out/，不要每次清空。
```

tmux 中运行长构建，SSH 断开不影响任务；`Ctrl-b d` 脱离、`tmux a` 查看，完成后退出该会话。也可在 tmux 内运行 `JOBS=8 ~/projects/kikiaosp_test/scripts/build-theme-picker.sh ~/aosp-master`，它同步、审计并记录构建日志。

本次 ThemePicker 构建共 5 分 16 秒，其中实际 ninja 执行 138 个增量步骤，不是完整重编。CP2A BoardConfig 将 product/system_ext 内容集成进 system；不要把旧独立分区的 WallpaperPicker2 误当当前运行应用。

## 镜像交付与冻结资产

正常产出为 `out/target/product/kikiaosp_test/{system,vendor}.img`。新产物另建清单并在 Windows 实测后才能替换默认基线。当前已验收文件固定于本仓库未追踪的 `output/`：

```text
system-kikiaosp-cp2a-theme-picker-20260930.img
vendor-kikiaosp-cp2a-theme-picker-20260930.img
product-kikiaosp-gallery-wallpaper-20260929.img
system_ext-kikiaosp-wallpaper-20260929.img
kikiaosp-runtime-support-20260926.tar.zst
```

后两份分区是当前冻结启动配对的兼容辅助磁盘；实际 CP2A 内容在 system 内。辅助包 SHA-256 `a8073fe77fc1e8a4e52f24af776955d6d9eae4ef5bd848d9dc703d8d4f1c363b`，含冻结 ramdisk、8 GiB F2FS userdata、misc 和空辅助盘。它不是 `m systemimage vendorimage` 的自动产物，字节一致 ramdisk 的源码重建配方尚未完成。二进制不进 Git，换构建机须另外迁移这些冻结资产；不要假设只 clone 仓库就拿到了它们。

内核在其独立仓库执行 `nix build`；Windows ARM64 QEMU 的固定上游提交、补丁、MSYS2 CLANGARM64 配方、相机桥接、SSH 收集器及启动命令均以 [KikiEmu README](https://github.com/kekeqwq/KikiEmu) 为准。三个仓库不混放职责。130 已退出当前构建，185 承担 Linux 构建，本地 Surface 做最终测试。

## 开发与隐私

功能另开分支，审计、增量构建、Windows 实测后合并 main。记录版本、manifest、镜像 SHA、启动参数和限制于 Work_5day.md。照片及 Windows 整桌截图含私人内容，只留本机 `~/Downloads/temp`，不提交；诊断日志、临时 patch、失败产物也不能当生产成果推送。用于干净回溯的 `/dev/sdb1` 源码盘已经同步完成并卸载，不在日常开发中修改。
