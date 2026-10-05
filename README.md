# KikiAOSP Test

## 0.3 Alpha: native FULL OTA

The user authorized publication from completed engineering tests. User-side real online OTA acceptance is deferred until a future 0.4 update; it is NOT claimed passed. [Release details](docs/RELEASE_0_3_ALPHA.md).

The format-2 physical A/B baseline is Android17 / Linux7.3-rc6, publisher sequence4. Settings and CLI use KikiUpdater / update_engine, preserving shared userdata. Create NEW0.3 storage; no0.2 disk migration. QEMU is unchanged from the audited0.2 five-patch native runtime. Historical0.1/0.2 format-1 guidance below does not define native0.3 updates.

面向 Windows ARM64 QEMU/WHPX 的 Android 17 测试设备。设备身份 `kikiaosp_test`，系统身份 `KikiAOSP`，产品目标 **`kikiaosp_test_arm64_phone-cp2a-userdebug`**；不是 Cuttlefish 手机产品。

本仓库负责 AOSP 设备树、集成补丁、精确 manifest、审计和镜像构建，并维护系统安装包标准及干净打包/发版流程。[0.1 Alpha 系统包](https://github.com/kekeqwq/kikiaosp_test/releases/tag/v0.1.0-alpha) 与 [KikiEmu 安装器](https://github.com/kekeqwq/KikiEmu/releases/tag/v0.1.0-alpha) 分别发布；终端用户不需要克隆这两个仓库。[kikiaosp_kernel](https://github.com/kekeqwq/kikiaosp_kernel) 负责内核；[KikiEmu](https://github.com/kekeqwq/KikiEmu) 负责 Windows ARM64 QEMU/相机桥接的源码构建、开发资产收集校验、本地测试，以及终端用户的配置管理器/系统安装器/桌面启动入口。Linux 开发机不承担最终 QEMU 测试。

## 0.1 Alpha 发布规划与固定协议

干净发行构建另选 `kikiaosp_test_arm64_phone_release-cp2a-userdebug`，设备仍为 `kikiaosp_test`；普通 phone 目标保留为 Dev。先完成 `scripts/prepare-clean-release.py` 的冻结源码审计，再用 `scripts/build-clean-release.py` 在新的独立输出中重建内核、system/vendor 和源码生成的 initramfs/boot-v4。完整命令、阶段记录及严格恢复规则见 [RELEASE_POLICY.md](RELEASE_POLICY.md#clean-release-build-target-and-pipeline)。这条新流水线产出的是候选输入，不等于 ZIP 打包或系统验收完成，旧开发 bundle 不参与发版。

0.1 已在独立源码／输出目录完成干净系统包生成、真实 Windows 系统回归，用户确认初始化成功并授权并入主线／发布 Alpha。完整来源和边界见 [发行记录](docs/RELEASE_0_1_ALPHA.md)。[RELEASE_FORMAT.md](RELEASE_FORMAT.md) 和双方固定 schema 定义当前 format-1；[RELEASE_POLICY.md](RELEASE_POLICY.md) 约束干净构建、许可/来源、版本演进和发布门槛。KikiEmu 消费同一合同，不能另行猜测文件名或私自更换包形式。以后0.2／0.3仍按同一格式打包测试，不更换用户读取形式。按用户2026-10-01的新要求，取消严格的独立 Dev 通道／并行隔离门槛，保留基本实例控制安全检查。

系统包与运行器独立模块化：本仓库的 ZIP 只交付系统必需文件、配套内核/initramfs 与来源/许可记录，不包含 QEMU、Windows 程序或用户磁盘。KikiEmu 的 create 另要求 `--qemu <bin目录>`；set 可更换兼容 QEMU 路径，下次启动生效，不改变已有系统/磁盘 ABI。合适的原生 ARM64 QEMU 构建步骤由 [KikiEmu 主线说明](https://github.com/kekeqwq/KikiEmu/blob/main/QEMU_BUILD.md) 维护，下载主线 build.ps1 到用户自己的 QEMU checkout 中构建，KikiEmu 自动补齐缺失运行依赖，无需手动 prepare.ps1。setup.exe/CLI 的用户视角测试仍交由用户；开发侧不执行安装器，只验证构建和系统。

共用机器合同已保存到 [contracts/format-1](contracts/format-1/README.md)，Windows 消费端按设备仓库提交和文件哈希固定引用，不在运行时下载浮动规范。Linux 使用 `python scripts/system-package.py --self-test` 检查24个共用清单样例，`python scripts/test-system-package.py` 检查15个隔离 ZIP/来源样例；`--validate /path/to/system.zip` 核验已有符合合同的包。这些只证明读取/拒绝规则，测试 ZIP 内核和文件系统是假数据，不可启动、不可发给用户当系统包。

真实候选的生产入口为 `scripts/package-clean-release.py --preparation PREP_RECORD --build-record BUILD_RECORD --output NEW_PACKAGE_DIRECTORY`。它拒绝未完成/开发目标，重核精确上游与冻结设备/内核、完整集成树、boot 配方和镜像哈希，将必要的 sparse 文件系统转换成 raw EROFS，并以本次构建的 fsck.erofs 检查镜像全部文件及实际 release 属性，保留镜像内生成的原始许可记录。最后只按 format-1 白名单生成 ZIP 和 SHA-256；额外本地 package-audit.json 不进包、不作为发布资产。11项隔离包装检查不代替真实构建；2026-10-01独立构建／实际包装已完成，Windows系统回归结果见下方候选记录，公开发版仍须用户验收。

源码生成boot/initramfs的配方和先前原型过程见 [BOOT_PAYLOAD.md](docs/BOOT_PAYLOAD.md)：当前产品静态first-stage init、tracked fstab和AOSP mkbootfs/mkbootimg，不使用历史recovery ramdisk。单盘GPT32／200 GiB可首次格式化完整F2FS、进入SDL/VirGL/120Hz桌面，并跨正常关机／重启保留数据；容量统计采用真实块盘与文件系统数据，见 [GPT存储原型记录](docs/GPT_STORAGE_PROTOTYPE.md)。旧原型资产不当发行包使用；本轮干净发行源／输出、真实ZIP和Windows回归另有独立身份与记录，见下方候选说明。

公开交付仅包含干净生成的系统安装材料（配套 kernel/initramfs 的 boot payload、EROFS system/vendor、清单及来源/许可）；不发布整盘、userdata、已初始化 misc/metadata 或旧支持 tarball。用户通过 KikiEmu 自行创建固定总容量、动态占用的磁盘，再安装系统。容量只在 create 时选择，创建后不可 set；内存/vCPU 等运行资源配置下次启动生效。

2026-10-01干净发行包 `KikiAOSP-0.1.0-alpha-arm64.zip` 为834421223字节，SHA-256为`73a184068b2c1b5576add96bcbadf4621bf3c3998c7f01fffeb624ee44aad42a`；只含boot/system/vendor、清单及来源／许可，不含用户磁盘或QEMU。Windows原生SDL/VirGL/120Hz下32／200 GiB新实例均已启动并保留数据重启，200 GiB还验证了移开原始ZIP后仍可启动。历史 R8 测试边界见 [KikiEmu候选记录](https://github.com/kekeqwq/KikiEmu/blob/main/CANDIDATE_TEST_20261001.md)，新管理器及最终发行材料见 [KikiEmu发行记录](https://github.com/kekeqwq/KikiEmu/blob/main/RELEASE_0_1_ALPHA.md)。用户授权发版不等于代理执行了安装器／公开 CLI 验收，也不等于所有硬件／商业 APK 均可用。

后续开发从该包基线修补源码，生成同格式新版本，交给KikiEmu在**新storage**中安装测试，再推进0.2、0.3。已有系统不自动替换；已发布版本的文件不覆盖。窗口和构建品牌保持KikiEmu／KikiAOSP；已有实例UUID、ADB／控制／相机端点及磁盘所有权核验保留，不再要求另一套Dev启动器和registry。

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

## 历史开发镜像与冻结资产（不是公开发版格式）

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

以上冻结文件只服务现有开发基线回溯，禁止作为 0.1 公开系统包的输入直接重新压缩/改名交付。发版必须补齐完整 ramdisk/boot 的源码生成配方，采用独立发布输出、精确 source-lock 和新的合同验证器；用户数据及空盘均由客户端全新创建。不得复用开发 userdata 或使用户实例引用开发目录中的资产。

## 开发与隐私

新增构建/打包脚本按其 `SPDX-License-Identifier: GPL-2.0-or-later` 使用 [GPL](LICENSE)。已有文件的许可标识优先，例如相机源码保持 Apache-2.0；上游代码及第三方组件保留原许可，不能因本项目选择 GPL 而统一重标。候选包会携带许可及来源记录，公开发版仍须完成对应源码/依赖许可审计。

功能另开分支，审计、增量构建、Windows 实测后合并 main。记录版本、manifest、镜像 SHA、启动参数和限制于 Work_5day.md。照片及 Windows 整桌截图含私人内容，只留本机 `~/Downloads/temp`，不提交；诊断日志、临时 patch、失败产物也不能当生产成果推送。用于干净回溯的 `/dev/sdb1` 源码盘已经同步完成并卸载，不在日常开发中修改。
