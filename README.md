# KikiAOSP Test

`kikiaosp_test` 是面向 Windows ARM 上 QEMU/WHPX 的原生 AArch64 Android 17 测试设备，不是 Cuttlefish 手机产品。产品目标为 `kikiaosp_test_arm64_phone`，系统身份为 `KikiAOSP`。此仓库保存设备树、相对 AOSP 上游的源码补丁、精确 manifest 快照与构建审计；[kikiaosp_kernel](https://github.com/kekeqwq/kikiaosp_kernel) 保存 4 KiB 主线内核，[KikiEmu](https://github.com/kekeqwq/KikiEmu) 保存 Windows 启动与截图脚本。

## 2026-09-26 验证状态

- AOSP 基线是 `android17-release`，不是 `master`。`manifests/aosp-verified-20260926.xml` 固定了本次测试的项目提交。升级上游应另开分支，重新生成补丁和验证镜像，不要把“最新分支”与“已验证快照”混为一谈。
- 已构建并在 Windows ARM 主机启动：Linux 7.3-rc4 4 KiB 内核、QEMU `virt`、WHPX、`virtio-gpu-pci`、Ranchu HWC3/minigbm。`sys.boot_completed=1`，默认桌面为 Launcher3QuickStep，Settings、三键导航、多任务和通知栏可见且可交互；ADB 经 `127.0.0.1:5555` 可用。
- 产品只保留 Launcher3、Settings 和必要的 SystemUI/输入法及基础服务。`KikiWindowTest` 源码保留作可选回归测试，但不预装、不自动启动。旧黑屏、绿点、原生测试层和动画 APK 的研究记录在 `Work_5day.md` 与 Git 历史中，不是当前产品配置。
- 当前 `system.img` 的 SHA-256：`002e67758ff9cec0cc7c31161ba3cf12be3fad7a8fdfd0e6e4c559dcc830c85e`。这是 `m -j8 systemimage` 的输出，且已在 Windows 端再次校验。
- 未验证动态分辨率、高刷、宿主 GPU 硬件渲染和真实扬声器播放。普通窗口可用；最大化仍会拉伸模糊或短暂黑屏。音频当前只是让 Framework 正常启动的软件输出路径，不能宣称已有声音。

## 目录与边界

```text
device/kiki/kikiaosp_test/         本设备及产品定义
patches/aosp-working-tree.patch   此快照下全部 AOSP tracked 源码改动；唯一应用入口
overlays/                         AOSP 上游树中新增的少量文件
manifests/                        已验证的 AOSP 精确项目修订
patches/qemu-*.patch              Windows ARM QEMU 的下游适配
scripts/                          同步、应用、审计和历史回归工具
Work_5day.md                      开发过程与实测日志
```

所有 Kiki 设备改动先在此仓库维护，再同步进 AOSP 工作树。不要把 Kiki 改动提交到 AOSP 上游仓库。`aosp-working-tree.patch` 是从测试过的 AOSP 工作树一次性生成的；旧的分片补丁不再应用，避免互相重叠。`scripts/audit-aosp-integration.sh` 要求 AOSP tracked 改动恰好由此补丁覆盖，并反向 dry-run 检查其内容。

## 从新 Linux 构建机准备 Android

至少预留 32 GiB 内存及约 250 GiB 磁盘。Arch Linux 示例：

```bash
sudo pacman -Syu
sudo pacman -S --needed git curl python unzip zip rsync bc bison flex gcc clang lld make ninja cmake cpio lz4 pigz openssl libelf libxml2 ncurses readline zlib perl schedtool fontconfig freetype repo
mkdir -p ~/projects ~/aosp-master
git clone https://github.com/kekeqwq/kikiaosp_test.git ~/projects/kikiaosp_test
git clone https://github.com/kekeqwq/kikiaosp_kernel.git ~/projects/kikiaosp_kernel
cd ~/aosp-master
repo init -u https://android.googlesource.com/platform/manifest -b android17-release --partial-clone --clone-filter=blob:limit=10M
```

要严格复现本次基线，将此仓库的快照作为 repo manifest 使用，而不是让 `android17-release` 浮动到新的提交：

```bash
cp ~/projects/kikiaosp_test/manifests/aosp-verified-20260926.xml .repo/manifests/kikiaosp-verified.xml
repo init -m kikiaosp-verified.xml
repo sync -c -j8 --fail-fast
```

在网络不稳定的开发机上，可按自己的代理配置设置 `HTTP_PROXY`、`HTTPS_PROXY` 后重试 `repo sync`；它会复用已下载对象。当前实验机使用过 `http://192.168.2.2:6152`，但这只是本地网络地址，不是项目依赖。

```bash
cd ~/projects/kikiaosp_test
scripts/apply-aosp-integration.sh ~/aosp-master
scripts/audit-device-tree-profile.sh
scripts/audit-aosp-integration.sh ~/aosp-master
cd ~/aosp-master
source build/envsetup.sh
lunch kikiaosp_test_arm64_phone-trunk_staging-userdebug
tmux new -s kikiaosp-build
m -j8 systemimage vendorimage
```

构建时按实际内存调整 `-j`；`out/` 应保留用于增量构建。`Ctrl-b d` 脱离 tmux，`tmux a -t kikiaosp-build` 查看；完成后关闭该会话。设备树更新后执行 `scripts/sync-device-tree.sh ~/aosp-master`，然后再次运行两项审计，避免 AOSP 工作树与此仓库版本不一致。上游 AOSP 更新后旧补丁可能不再适用，需要在独立升级分支解决冲突并重测。

如需从当前已测试的 AOSP 工作树收敛新源码改动：

```bash
cd ~/projects/kikiaosp_test
scripts/refresh-aosp-working-tree-patch.sh ~/aosp-master
scripts/audit-aosp-integration.sh ~/aosp-master
```

内核独立构建：

```bash
cd ~/projects/kikiaosp_kernel
nix build
ls -lh result/boot/kernel result/boot/config
```

应核对内核配置、4 KiB 页大小和目标镜像的 SHA-256 后再替换已验证产物；本次 Windows 基线使用 `kernel-linux-7.3-rc4-4k-netfilter-20260925`。

## Windows ARM QEMU 与启动

在 Windows ARM 的 MSYS2 **CLANGARM64** 环境中构建原生 ARM64 QEMU，不要使用 x86_64 UCRT64 目标。将上游 QEMU 固定在 `5f664cd37aec17e8145aa117d8da68f507edc8f1`，依次应用 `patches/qemu-windows-gtk-full-redraw.patch` 和 `patches/qemu-windows-arm64-gtk-touch.patch`；前者修复 GTK 部分重绘，后者是当前触摸坐标及 Windows ARM 构建适配。按照上游 QEMU 的 Windows/MSYS2 依赖说明安装 GTK3、编译工具和相关库，至少构建 `aarch64-softmmu` 并启用 GTK/WHPX；产物 PE Machine 应为 `0xAA64`。当前实测 QEMU 源码处于首个补丁形成的提交 `bde658e` 加第二个补丁的工作树状态，构建出的本机程序为 ARM64 PE。

将编译好的 `qemu-system-aarch64.exe` 放在 Windows 启动仓库 `tools/qemu-src/build/`，把内核、ramdisk、system/vendor/data/misc/空分区镜像放在 `aosp/windows-arm64-test/`。文件名及启动参数以该仓库 [README](https://github.com/kekeqwq/KikiEmu) 和 `tools/run_kikiaosp_touch_local.ps1` 为准：

```powershell
.\tools\run_kikiaosp_touch_local.ps1
adb connect 127.0.0.1:5555
adb shell getprop sys.boot_completed
```

脚本使用 `-snapshot`，本次运行不会写回基础磁盘。测试结束要关闭 QEMU 窗口。截图只留在本机 `~/Downloads/temp/`，不要把整张桌面证据意外上传 GitHub。

## 开发约束

在 `feature/<name>` 分支做改动，跑完审计与对应构建/Windows 实测后再快进合并 `main`。只在设备树仓库和内核仓库开发各自内容；KikiEmu 仓库是本机启动入口。每个稳定里程碑记下 AOSP manifest、内核版本、镜像哈希、实际 QEMU 参数、ADB/画面结论与未解决问题；历史详见 `Work_5day.md`。
