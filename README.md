# KikiAOSP Test

`kikiaosp_test` 是面向 Windows ARM 上 QEMU/WHPX 的原生 AArch64 Android 17 测试设备，不是 Cuttlefish 手机产品。产品目标为 `kikiaosp_test_arm64_phone`，系统身份为 `KikiAOSP`。此仓库只负责 AOSP 设备树、源码补丁、精确 manifest、构建审计及 Android 镜像产出；[kikiaosp_kernel](https://github.com/kekeqwq/kikiaosp_kernel) 只负责内核；[KikiEmu](https://github.com/kekeqwq/KikiEmu) 负责 QEMU 补丁/构建、取得产物、校验、打包和 Windows 启动。

## 2026-09-26 验证状态

- AOSP 基线是 `android17-release`，不是 `master`。`manifests/aosp-verified-20260926.xml` 固定了本次测试的项目提交。升级上游应另开分支，重新生成补丁和验证镜像，不要把“最新分支”与“已验证快照”混为一谈。
- 已构建并在 Windows ARM 主机启动：Linux 7.3-rc4 4 KiB 内核、QEMU `virt`、WHPX、`virtio-gpu-pci`、Ranchu HWC3/minigbm。`sys.boot_completed=1`，默认桌面为 Launcher3QuickStep，Settings、三键导航、多任务和通知栏可见且可交互；ADB 经 `127.0.0.1:5555` 可用。
- 产品只保留 Launcher3、Settings 和必要的 SystemUI/输入法及基础服务。`KikiWindowTest` 源码保留作可选回归测试，但不预装、不自动启动。旧黑屏、绿点、原生测试层和动画 APK 的研究记录在 `Work_5day.md` 与 Git 历史中，不是当前产品配置。
- 当前主线 `system.img` 的 SHA-256：`13c41b3d33b718075713d1472590a57b385f25610a2523bbe79d92a086df3636`。当前 `vendor.img` 的 SHA-256：`67616fae719997d6a779e8d1c8a99c0de2ee8b7a72aa05c97c480bba56322eb2`。二者已在 Windows ARM 上与 dma-buf 内核一起启动。此前动态分辨率配对的 system/vendor 分别是 `002e67758ff9cec0cc7c31161ba3cf12be3fad7a8fdfd0e6e4c559dcc830c85e` 和 `674652a3e965c36b20fd50eff2e3bd7c7a2ae1553cc8a76be3d1ed0925efb396`。
- 主线（原 `feature/native-resolution-20260926`）已验证真实像素动态分辨率：默认手机窗口 864×1728、Surface 最大化 2784×1876、任意横向窗口 2374×1530，并能恢复到 864×1728。HWC 保留同一 Android 显示对象并原位更新参数，避免模式切换时销毁 layer、重启 SurfaceFlinger 或产生假的断开事件。Windows 全桌截图确认 Android 四边、状态栏和三键导航完整显示，不是旧画布拉伸，也不是只显示左上角。高刷和宿主 GPU 硬件渲染仍未验证。真实扬声器已经验证：PCM、设置点按音和铃声试听都可以从 QEMU DirectSound 播出。点按音与铃声试听依赖 AIDL Codec2 和内核的 dma-buf system heap。

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
| `system.img` | 1,051,099,136 字节 | `13c41b3d33b718075713d1472590a57b385f25610a2523bbe79d92a086df3636` |
| `vendor.img` | 94,040,064 字节 | `67616fae719997d6a779e8d1c8a99c0de2ee8b7a72aa05c97c480bba56322eb2` |

当前 system/vendor 已与 dma-buf 内核在 Windows ARM 上启动：Launcher3、Settings、Ethernet、扬声器 PCM、点按音和铃声试听可用。动态分辨率下 SurfaceFlinger 与 Launcher3 不重启的结论属于此前 vendor `674652a3e965c36b20fd50eff2e3bd7c7a2ae1553cc8a76be3d1ed0925efb396`，本次没有单独重测。不要把更早的扫描测试镜像与当前产物混称。

本次运行还依赖一个冻结的辅助包：`output/kikiaosp-runtime-support-20260926.tar.zst`，SHA-256 `a8073fe77fc1e8a4e52f24af776955d6d9eae4ef5bd848d9dc703d8d4f1c363b`。它从已验证 Windows 运行资产归档，含启动 ramdisk、空 product/system_ext/odm、F2FS userdata 和 misc；不是本次 `m systemimage vendorimage` 自动生成，也不纳入 Git。开发机 185 已保存该归档；换构建机时须另行迁移相同归档，不能假装从当前源码可直接重建出相同哈希。

本仓库只交付 Android 镜像与必要的构建信息，不再存放 QEMU 补丁或 Windows 启动脚本。主仓库 [KikiEmu README](https://github.com/kekeqwq/KikiEmu) 中的清单及收集脚本会经 SSH 取回 Android 产物、内核和辅助包，验证 SHA-256 后形成可启动目录。测试结束关闭 QEMU；桌面截图只留本机，不上传此仓库。

### 实验分支：Mesa VirGL 原生合成

`feature/gpu-virgl-20260927` 不替代上表的软件稳定基线。该分支在 Kiki 产品中加入 AOSP 自带的 SDV ARM64 Mesa VirGL 预编译库，并将 `patches/aosp-working-tree.patch` 中的旧 CPU 合成兜底限制在非 Mesa 模式。启动参数 `androidboot.hardwareegl=mesa` 才选择原生 GPU 缓冲路径；默认 `angle` 仍走已验证的软件路径。复现时先切到此分支，再按照上文的 `apply-aosp-integration.sh`、审计和 `m -j8 systemimage vendorimage` 流程构建，不要在已打过补丁的 AOSP 工作树上重复应用。

本分支已构建的候选镜像（尚未完成画面与性能验收）为：`system.img` 1,051,099,136 字节，SHA-256 `ba20dd6a8b09dcd482c1564c9718b84ac6d330c19a1d82ee78cf9aabf8701202`；`vendor.img` 99,700,736 字节，SHA-256 `f60fee46addc3f6bdaa3ebe1f2aa55ce0eeafd1678c6f314d6279ff7d11ac4e7`。第一次 VirGL vendor 测试已能启动 Android 并报告 `GLES: Mesa/X.org, virgl`，但旧 system 的 CPU 合成路径输出全黑；本节新的 system 镜像正针对这一点。配套的 Windows WGL QEMU 补丁、镜像收集 profile 和实测证据在 KikiEmu 主仓库的同名功能分支。

SDV 的三份 Mesa 预编译库来自较旧版本，ELF LOAD 对齐为 4 KiB；本实验只配合现有 4 KiB 内核。产品级 `PRODUCT_CHECK_PREBUILT_MAX_PAGE_SIZE := false` 仅为让这批预编译库进入候选镜像，不代表其可用于 16 KiB 内核；后续若测试 16 KiB，需先重新编译 Mesa 库并恢复检查。

## 开发约束

在 `feature/<name>` 分支做改动，跑完审计与对应构建/Windows 实测后再快进合并 `main`。构建相关改动归本仓库或内核仓库；QEMU 和 Windows 打包/启动相关改动归 KikiEmu 主仓库。每个稳定里程碑记下 AOSP manifest、内核版本、镜像哈希、实际 QEMU 参数、ADB/画面结论与未解决问题；历史详见 `Work_5day.md`。

## 主线：Ethernet 与扬声器

原 `feature/network-audio-20260926` 已并入主线。QEMU `virtio-net-pci` 使用 Kiki Connectivity 覆盖层：`eth0` 静态地址 `10.0.2.15/24`、网关 `10.0.2.2`、DNS `10.0.2.3`，并声明 `android.hardware.ethernet`。客体不提供 Wi-Fi 或移动数据，出站走宿主现有路由。TCP ADB 仍是 `127.0.0.1:5555`。

音频使用 AOSP AIDL primary HAL 和本设备的 Speaker 策略，对应 ALSA card 0/device 0。媒体流默认音量是 15/15，实际听感由 Windows 上 QEMU 的音量控制。产品属性 `media.c2.hal.selection=aidl` 注册真正的软件 Codec2；默认的 `hidl` 只会发布空服务，因此没有 `c2.android.vorbis.decoder`，点按音和铃声试听无法解码。这个解码器还要求内核提供 `/dev/dma_heap/system`。

Windows 已实测应用可见的 Ethernet、扬声器 PCM、声音设置里的点按音，以及铃声选择器试听。配套内核是 `result/boot/kernel`，SHA-256 `f33ef2371736dfd75122eaaf277223321117b57e572e235b5b35f558aa14db96`。
