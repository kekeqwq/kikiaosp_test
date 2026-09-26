# KikiAOSP Test

`kikiaosp_test` 是面向 Windows ARM 上 QEMU/WHPX 的原生 AArch64 Android 17 测试设备，不是 Cuttlefish 手机产品。产品目标为 `kikiaosp_test_arm64_phone`，系统身份为 `KikiAOSP`。此仓库只负责 AOSP 设备树、源码补丁、精确 manifest、构建审计及 Android 镜像产出；[kikiaosp_kernel](https://github.com/kekeqwq/kikiaosp_kernel) 只负责内核；[KikiEmu](https://github.com/kekeqwq/KikiEmu) 负责 QEMU 补丁/构建、取得产物、校验、打包和 Windows 启动。

## 2026-09-26 验证状态

- AOSP 基线是 `android17-release`，不是 `master`。`manifests/aosp-verified-20260926.xml` 固定了本次测试的项目提交。升级上游应另开分支，重新生成补丁和验证镜像，不要把“最新分支”与“已验证快照”混为一谈。
- 已构建并在 Windows ARM 主机启动：Linux 7.3-rc4 4 KiB 内核、QEMU `virt`、WHPX、`virtio-gpu-pci`、Ranchu HWC3/minigbm。`sys.boot_completed=1`，默认桌面为 Launcher3QuickStep，Settings、三键导航、多任务和通知栏可见且可交互；ADB 经 `127.0.0.1:5555` 可用。
- 产品只保留 Launcher3、Settings 和必要的 SystemUI/输入法及基础服务。`KikiWindowTest` 源码保留作可选回归测试，但不预装、不自动启动。旧黑屏、绿点、原生测试层和动画 APK 的研究记录在 `Work_5day.md` 与 Git 历史中，不是当前产品配置。
- 当前 `system.img` 的 SHA-256：`002e67758ff9cec0cc7c31161ba3cf12be3fad7a8fdfd0e6e4c559dcc830c85e`。这是 `m -j8 systemimage` 的输出，且已在 Windows 端再次校验。当前分辨率验证的 `vendor.img` SHA-256 为 `674652a3e965c36b20fd50eff2e3bd7c7a2ae1553cc8a76be3d1ed0925efb396`。
- 主线（原 `feature/native-resolution-20260926`）已验证真实像素动态分辨率：默认手机窗口 864×1728、Surface 最大化 2784×1876、任意横向窗口 2374×1530，并能恢复到 864×1728。HWC 保留同一 Android 显示对象并原位更新参数，避免模式切换时销毁 layer、重启 SurfaceFlinger 或产生假的断开事件。Windows 全桌截图确认 Android 四边、状态栏和三键导航完整显示，不是旧画布拉伸，也不是只显示左上角。高刷、宿主 GPU 硬件渲染和真实扬声器播放仍未验证；音频当前只是让 Framework 正常启动的软件输出路径。

## 目录与边界

```text
device/kiki/kikiaosp_test/         本设备及产品定义
patches/aosp-working-tree.patch   此快照下全部 AOSP tracked 源码改动；唯一应用入口
overlays/                         AOSP 上游树中新增的少量文件
manifests/                        已验证的 AOSP 精确项目修订
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

## Android 镜像产出与交接

本次已测试的 Android 产物位于开发机 `~/aosp-master/out/target/product/kikiaosp_test/`：

| 文件 | 大小 | SHA-256 |
| --- | ---: | --- |
| `system.img` | 1,041,625,088 字节 | `002e67758ff9cec0cc7c31161ba3cf12be3fad7a8fdfd0e6e4c559dcc830c85e` |
| `vendor.img` | 94,035,968 字节 | `674652a3e965c36b20fd50eff2e3bd7c7a2ae1553cc8a76be3d1ed0925efb396` |

当前 `vendor.img` 已配合上述系统镜像、带 VirtIO GPU EDID 同步补丁的 rc4 内核与运行辅助磁盘在 Windows ARM 上重新启动；ADB、Launcher3、Settings、多任务窗口、触摸和动态尺寸均可用。模式切换实测过程中 SurfaceFlinger PID 与 Launcher3 PID 均未变化。不要把更早的 `vendor-kikiaosp-ui-scanout-pixel-count-20260926.img` 与当前产物混称为同一镜像。

本次运行还依赖一个冻结的辅助包：`output/kikiaosp-runtime-support-20260926.tar.zst`，SHA-256 `a8073fe77fc1e8a4e52f24af776955d6d9eae4ef5bd848d9dc703d8d4f1c363b`。它从已验证 Windows 运行资产归档，含启动 ramdisk、空 product/system_ext/odm、F2FS userdata 和 misc；不是本次 `m systemimage vendorimage` 自动生成，也不纳入 Git。开发机 185 已保存该归档；换构建机时须另行迁移相同归档，不能假装从当前源码可直接重建出相同哈希。

本仓库只交付 Android 镜像与必要的构建信息，不再存放 QEMU 补丁或 Windows 启动脚本。主仓库 [KikiEmu README](https://github.com/kekeqwq/KikiEmu) 中的清单及收集脚本会经 SSH 取回 Android 产物、内核和辅助包，验证 SHA-256 后形成可启动目录。测试结束关闭 QEMU；桌面截图只留本机，不上传此仓库。

## 开发约束

在 `feature/<name>` 分支做改动，跑完审计与对应构建/Windows 实测后再快进合并 `main`。构建相关改动归本仓库或内核仓库；QEMU 和 Windows 打包/启动相关改动归 KikiEmu 主仓库。每个稳定里程碑记下 AOSP manifest、内核版本、镜像哈希、实际 QEMU 参数、ADB/画面结论与未解决问题；历史详见 `Work_5day.md`。

## Ethernet 与扬声器功能分支

`feature/network-audio-20260926` 为 QEMU 的 `virtio-net-pci` 增加 Kiki 专属 Connectivity 资源覆盖层：`eth0` 使用静态地址 `10.0.2.15/24`、网关 `10.0.2.2`、DNS `10.0.2.3`，并声明 `android.hardware.ethernet`，供 Android EthernetService 注册应用可见的默认网络。原有的早期地址和策略路由仍用于 TCP ADB；客体没有 Wi-Fi 或移动数据设备。

音频沿用 AOSP AIDL primary HAL 与本设备的 Speaker 策略，面向 ALSA card 0/device 0。设备树将 Android 媒体流默认音量设为 15/15，启动脚本也会处理旧 userdata 内保存的较低音量。实际播放还需要匹配的 `CONFIG_SND_VIRTIO` 内核和 Windows QEMU 的 DirectSound 后端。镜像构建通过后仍需在 Windows 客机验证 APK 联网及真实扬声器输出。

185 上该功能分支的镜像已构建：`system.img` SHA-256 `963305ad2423ab2dc5bd27e7d4488ff4dbe1462a035190f45437289a0ea57cf4`，`vendor.img` SHA-256 `65411e95dedf1755aaff006354d8a88982fe23e4688e91553b53e6151780c5e1`。Windows 主仓库的 `profiles/network-audio-20260926.json` 固定上述镜像和新内核的配对，运行实测尚未完成。
