# KikiAOSP Android 17 启动依赖核查与一次性恢复方案

日期：2026-09-25。状态：**供审查的方案，尚未执行整体恢复**。

目标：Windows ARM 本地 QEMU 中，Android 正常启动，原生 APK Activity 显示 TEST OK、产生至少两帧可见变化，并可通过应用内关闭按钮返回 Launcher；保留 Settings、Launcher3QuickStep、SystemUI（状态栏、通知栏）。设备仍为 `kikiaosp_test`，产品仍为 `kikiaosp_test_arm64_phone`，系统为 KikiAOSP。

## 1. 结论及范围

当前失败具有共同原因：Kiki 的精简补丁切断了标准 Framework 启动流程，创建部分对象后提前进入“就绪”，同时 init 又停止这些对象所依赖的 native 服务。应一次性恢复**标准 Framework 的启动和生命周期**，将精简放在产品应用、硬件能力声明和虚拟设备实现上。

这份清单区分三个概念：

- **K：核心契约**。进程、包、权限、用户、存储、显示、输入和启动生命周期。不能通过吞异常、虚假的 ready 属性、空 Binder 来替代。
- **U：当前 UI 目标的保守保留集**。保留原版 SystemUI、Launcher、Settings 后随之保留的服务。它们不全是“任意一个最简单 Activity”理论上必需的，但这轮不能再按名称猜测其可删性。
- **O：有上游条件分支的可选能力**。按 feature、资源、构建 flag 和产品配置关闭；必要的 Manager/Binder 接口仍须满足调用者的契约。

**不是声称存在一份对所有 Android 版本、产品、flag 都通用的几十项最小集合。**本次避免遗漏的实现规则是：恢复当前固定版本的标准启动调用及其原有条件；不用人工白名单取代它。下表是重点核查清单，完整的直接 Java 服务启动/注册调用点另见 [调用点清单](android17-systemserver-startup-inventory.tsv)。其中 263 个调用点包含互斥、可选和动态注册，**不等于要同时启动 263 个服务**，也不是运行时依赖闭包的证明。

本次已核查：正常及 Kiki 修改后的 SystemServer、SystemServiceManager、AMS、PowerManager、DisplayManager、DevicePolicy/Role 启动、SystemUI 的 FrameworkServicesModule/初始化入口、部分 WM Shell、产品继承、native init、KeyMint/GateKeeper 等 HAL 模块定义。动态 APEX 服务、运行时资源和所有 Settings 页面不能仅凭一个静态列表完全证明；方案用保留上游启动规则和实际产品清单覆盖它们，最后做运行验收。

## 2. 固定源码基线

本次没有 repo sync，没有更新上游版本。

| 仓库 | 核查的 HEAD |
| --- | --- |
| manifest | `ad156f32caaa06dae91c02d443f6a8fe210eaa54`，提交说明为 Update android-latest-release to android17-release |
| frameworks/base | `94b4c163b7dfe5ce3607f7bb8456f9573f7de57d` |
| packages/modules/Permission | `1093eca7407576c72e51b1a88550ee0667a6e5dc` |
| system/core | `545d2487e38192a2ce25040897ced877cf6b4f53` |
| frameworks/native | `ae266dcb706d083868578cfedce381ef44488a07` |
| hardware/interfaces | `0162af698935100a590b7359581ac8b1b80693e5` |

AOSP 路径：185 的 `/home/keke/aosp-master`。设备仓库：`/home/keke/projects/kikiaosp_test`。

现有产品实际继承的是 `build/make/target/product/aosp_arm64.mk`，它进一步继承 generic_system、handheld_system_ext、telephony_system_ext、aosp_product 和 generic_arm64 的 vendor 配置；**不是正在编译 aosp_cf 产品**。设备文件中提到“继承 Cuttlefish”的旧注释已经不准确，后续应修订。恢复 Framework 不需要改回 Cuttlefish 产品或使用 Habumi。

## 3. 这次已确认的结构性问题

| 证据 | 对启动的影响 |
| --- | --- |
| Kiki 在 `startOtherServices()` 的显示/输入初始化后进入自建分支，调用部分 ready 回调后 return | 正常路径后面的 Accessibility、JobScheduler、Trust、LauncherApps、网络、音频等大量启动代码无法执行 |
| SystemServiceManager 用类名白名单过滤 phase >= 200 的串行回调，并捕获异常后 continue | “服务已注册”不代表“服务已完成初始化”。该过滤还没有同样覆盖上游并行 phase 路径，行为受 flag 影响 |
| 精简分支发出 500、550、600，却省略标准 480 和 520，以及多个显式 ready 调用 | 单补 startService 不能恢复生命周期；DevicePolicy 的 480 分支有实际初始化工作 |
| PowerManagerService 未进入当前 phase 白名单 | 其 500 回调才会执行 systemReady，连接显示、窗口、电池和传感器等；直接关系到显示电源状态，不能略过 |
| `DisplayManagerService.windowManagerAndInputReady()` 被跳过 | 不会完成 Window/Input/Activity/DeviceState 关联及相应显示遍历调度 |
| root init 停止 keystore2，跳过 earlyBootEnded/module-hash 握手和 BPF 加载；设备 rc 在 audioserver/netd/KeyMint 等进入 running 后 stop | 即使补上 LockSettings、网络、音频 Java 服务，下层仍可能缺失、等待或反复退出 |
| 存在 SystemServer 启动异常后的 fail-open、WMS/Input 初始化异常吞掉继续等代码 | 后续 NullPointer/DeadSystem 可能只是更早失败的后果，不应据此判断缺哪个 APK |
| 产品配置、AOSP 补丁、增量 repack 镜像分别携带启动配置 | 必须审计最终产物的一致性，不能只看设备 mk 或某个 jar |

具体源码位置（行号对应本次核查快照）：

- 修改后的 `frameworks/base/services/java/com/android/server/SystemServer.java`：约 1216 的 fail-open；2134 的 display/input ready 跳过；2145 起的 minimal shortcut。
- 修改后的 `services/core/java/com/android/server/SystemServiceManager.java`：324 起的 phase 白名单及异常跳过；其后的并行回调没有相同过滤。
- `services/core/java/com/android/server/power/PowerManagerService.java`：1412 的 onBootPhase；1446 起的 systemReady。
- `services/core/java/com/android/server/display/DisplayManagerService.java`：913 的 windowManagerAndInputReady。
- **原版 HEAD** SystemServer：3150 的 LockSettings.systemReady；3160 注明 DevicePolicy 初始化需要 480；3205 的 500；3318 的 520。
- `services/devicepolicy/java/com/android/server/devicepolicy/DevicePolicyManagerService.java`：1813 起构造依赖；2921 起的各 phase 初始化。设备管理 feature 关闭时它有自己的上游裁剪分支，应保留该分支，而不是自行丢掉接口。
- `system/core/rootdir/init.rc`：17 停止 keystore2；540 跳过 BPF；715 和 1036 跳过 keystore 握手。
- 设备仓库 `device/kiki/kikiaosp_test/kiki-minimal-native.rc`：early-init 和 running 属性触发器中的 stop 规则。

### v104–v106 的正确归档状态

- Settings、SettingsProvider、Launcher3QuickStep、SystemUI 均在产物中；之前 PackageManager 的现场查询也能解析。不存在“因为 Settings.apk 没装而导致这一轮崩溃”的证据。
- v104 现场 crash buffer：RoleController 的 SystemSupervisionRoleBehavior 调用空 SupervisionManager，导致 system_server 退出；SystemUI 的 DeadSystem 异常是后果。
- v105 启动 SupervisionService 后，RoleController 继续在 DevicePolicyManagementRoleBehavior 上因 DevicePolicyManager 为空而崩溃。system_server 重复重启；Windows 前台截图仍黑。测试 QEMU 已关闭。
- v105 system SHA-256：`58dbd9132292128862faa276d3e52ce6a3f8d8dfd114198322f5eddfa4a8b80c`。
- v106 只完成 services 增量编译（24 个 Ninja actions，1:35），加入 LockSettings/DevicePolicy 启动及回调白名单。**没有打包、启动或验证 v106 镜像**。静态核查已发现该方案仍缺少标准 480/显式 ready 流程，不将它作为完整修复继续试。
- 目前不能宣称 Android 原生 APK UI 成功或完整 Framework 稳定。

## 4. 必须恢复的启动流程

官方文档描述 init 启动 Zygote，Zygote 承担系统与应用进程派生；具体服务顺序以本次固定版本 SystemServer 源码为准。[Zygote 文档](https://source.android.com/docs/core/runtime/zygote)

启动主干：

```text
内核 / 分区 / Binder / SELinux 文件系统及上下文
    → init：挂载、环境、属性、native 服务、APEX 与 linker namespaces
    → ART / Zygote64 → system_server
    → bootstrap / core / other / APEX 服务（按上游顺序和条件）
    → 用户生命周期、应用数据、SystemUI / HOME、窗口首次绘制
    → Framework 自己完成 boot；sys.boot_completed=1
```

启动 phase 与显式 ready 调用穿插在上述流程中，不能把下表理解为所有服务先启动再统一发送 phase：

| 阶段 | 必须保留的语义 |
| --- | --- |
| 100：WAIT_FOR_DEFAULT_DISPLAY | 默认显示真实存在；DMS 能取得 SurfaceFlinger 提供的显示 |
| 200：WAIT_FOR_SENSOR_SERVICE | 等待传感器服务初始化完成；无物理传感器也要正确处理服务协议/空设备能力 |
| 480：LOCK_SETTINGS_READY | 先完成 LockSettings.systemReady；随后让依赖锁设置的服务初始化 |
| 500：SYSTEM_SERVICES_READY | PowerManager、PackageManager 等核心服务可用；各服务正常执行自己的回调 |
| 520：DEVICE_SPECIFIC_SERVICES_READY | 设备资源指定的服务已处理完毕 |
| 550：ACTIVITY_MANAGER_READY | ActivityManager 准备好，服务可发送相应广播 |
| 600：THIRD_PARTY_APPS_CAN_START | 满足应用启动/绑定条件；相关网络、用户、服务就绪动作按原版执行 |
| 1000：BOOT_COMPLETED | 由正常 AMS/WMS/应用启动完成路径到达；不手工设置 boot_completed |

还需要保持原版的：AMS 与 WMS 绑定、WMS.onInitReady/displayReady/systemReady、DMS.windowManagerAndInputReady/systemReady、PackageManager 等待 app-data 准备、LockSettings.onThirdPartyAppsStarted，以及用户 starting/unlocking/unlocked 回调。

`ActivityManagerService.finishBooting()` 还会等待启动动画完成、通知 ART、提交存储 checkpoint、发送 phase 1000，最后设置 boot_completed。跳过/停止 bootanimation 时也必须满足原版退出与完成通知协议；看到 ADB 或进入 Looper 不能代替这些条件。

## 5. 按依赖关系整理的保留清单

下表是本轮实现与验收的分组，不是新的手写启动白名单。凡未单独列出的上游默认服务，仍遵循原来的启动条件。

| 组别 | 本轮保留/恢复的组件 | 核查重点 |
| --- | --- | --- |
| K：进程与 IPC | init、ueventd、servicemanager、Binder/binderfs；实际保留 HIDL 时的 hwservicemanager；Zygote64、ART、system_server、AMS、ATMS | 服务发现、fork、应用 UID、进程组、上下文与 ABI 一致 |
| K：包与权限 | Installer/installd、PackageManager、UserManager、AccessChecking/PermissionManager、AppOps、PermissionPolicy、UriGrants、ArtManagerLocal、PlatformCompat、FeatureFlags、SystemConfig | APK 扫描、签名、权限、用户 0、dex/namespace 和 app-data 准备完整 |
| K：配置与资源 | framework-res、ResourcesManager、OverlayManager、SettingsProvider、DeviceConfig 相关服务/模块、ContentService、AccountManager 后端 | RRO 真正生效；provider 能打开；AccountManager 在 ContentService 前；无需安装云账户认证器或同步 APK |
| K：数据与挂载 | vold、StorageManager、installd/app-data、匹配的 APEX/linkerconfig、/data/user、user_de、data_mirror、metadata 及权限/标签 | Zygote 能挂载应用数据；用户解锁与存储 ready 正常；不混用历史 no-APEX 别名资产 |
| K：窗口与输入 | WMS、DMS、InputManager、InputMethodManager、DeviceState、UiMode、PowerManager，及上游 PhoneWindowManager 策略 | 服务注册之外，显式绑定/ready/phase 都必须完成；IMMS 不能因为不用软键盘就删除 |
| K：真实渲染 | SurfaceFlinger、BufferQueue/SurfaceControl、allocator/mapper、RenderEngine/EGL/Vulkan 实际选用后端、HWC3、DRM/KMS、virtio-gpu | 保留已验证的图形适配；应用层 buffer 必须真正呈现到宿主 QEMU |
| K/U：角色与用户策略 | RoleService/RoleController、Supervision、DevicePolicy、UsageStats、用户/权限依赖 | 当前 Android 17 RoleController 路径直接查询 Supervision 和 DevicePolicy；DPM 构造还要求 UsageStats 等 |
| K/U：凭据与解锁 | LockSettings、Trust、keystore2、gatekeeperd、软件 KeyMint/GateKeeper、vold 用户存储 | 不设 PIN 不等于可以删除后端；测试设备可使用 AOSP 软件实现，无需物理 TEE |
| K/U：电源与无硬件接口 | Power/SystemSuspend、Battery/BatteryStats、Health、SensorService、SensorPrivacy、DeviceState；标准 Lights/Thermal 等启动分支 | 使用正确的虚拟/无硬件语义；不能删 Binder 后把用户设为“无电池/无传感器”就算完成 |
| U：调度与状态 | AlarmManager、JobScheduler、DeviceIdle、UsageStats/AppStandby、StorageStats、AppHibernation、上游统计/模块服务 | PermissionController、通知、设置等有跨模块调用；对象和 boot/user 回调必须完整 |
| U：SystemUI/桌面 | StatusBar、Notification、Accessibility、LauncherApps、Shortcut、AppWidget、Wallpaper、Clipboard、ColorDisplay、字体/文本/Locale/GrammaticalInflection | Launcher 和状态/通知栏并非单独放入 APK 即可；保留原版 SystemUI/WM Shell 的框架接口 |
| U：网络框架 | netd、BPF 加载/DNS、NetworkStack/Connectivity、NetworkManagement、NetworkPolicy、NetworkStats、NetworkScore、VPN；TelephonyRegistry 的正常接口 | UI/Settings 可以显示未连接/无 SIM；不需提供基带或电话应用，但网络管理 API 不能随意消失 |
| U：音频与媒体控制 | AudioService、audioserver、所选音频 HAL、MediaSession、MediaRouter、MediaProjection 的框架服务 | 原版 SystemUI 包含音量和媒体控制依赖；摄像头/视频应用仍可不装；音频实际输出另作验收 |
| U：模块与平台支持 | 当前产品实际需要的 ART、ICU、时区、Conscrypt、Permission、Stats、Connectivity 等 APEX及其 classpath/service 描述；上游动态 APEX 服务 | 不凭名称删除 APEX，不跨版本拼接 jar/.so/APEX；按最终产品/flag 解析 |
| U：故障可观测性 | logd、tombstoned、DropBox、Watchdog、lmkd、上游必要的资源/进程监控 | 这组不等同于每个像素的理论硬依赖；保留用于可诊断、可长期运行的系统基线 |

图形路径与应用启动路径是两项关联但不同的验收。官方文档说明 WindowManager 管理窗口并向 SurfaceFlinger 提供窗口信息，SurfaceFlinger/HWC 再合成和输出；已有绿点只证明此前验证过的图形范围。[SurfaceFlinger/WindowManager](https://source.android.com/docs/core/graphics/surfaceflinger-windowmanager) · [图形架构](https://source.android.com/docs/core/graphics/architecture)

### 原版 SystemUI 为什么扩大了保留范围

本版本 `packages/SystemUI/src/com/android/systemui/dagger/FrameworkServicesModule.java` 中包含非 Nullable provider：Accessibility、Alarm、Audio/IAudioService、Connectivity、VPN、DevicePolicy、Display、DeviceState、JobScheduler、Input/IMMS、StatusBar、Keyguard、LauncherApps、Power/DeviceIdle、UsageStats、Role、Sensor/SensorPrivacy、Shortcut、Storage、Trust、Notification、Media 等。

`SystemUIInitializer.init()` 先构造 WMComponent，再取得 Shell 等组件并初始化 SysUI/Dependency。故异常可能在内容 provider 安装阶段就出现，早于状态栏绘制。

这里有两项边界：

1. provider 的非 Nullable 声明**不是**该组件在所有配置中都会立即实例化的证明；部分 Manager 也可以在没有硬件 Binder 时存在。
2. 它足以说明“没有物理设备，所以随意删除所有同名 Framework 服务”不可靠。本轮保留原版接口和条件分支，后续精简才逐一证明调用方的 Optional/feature 处理。

同文件对 Face、Fingerprint、部分 VR/ContextHub/VirtualDevice/Wifi 等有 Nullable 或 feature 条件，可以沿这些明确的上游边界关闭能力。

### 当前 RoleController 错误的完整上下文

```text
用户 starting → RoleService → 默认角色授予
                              ├─ SupervisionManager
                              └─ DevicePolicyManager
                                   ├─ UserManager / PackageManager / Permission
                                   ├─ UsageStats / RoleManager
                                   └─ LockSettings 与标准 480 阶段
                                        └─ 凭据、GateKeeper/KeyMint、用户存储
```

该图表示依赖关系，不表示 DPM 必须先于 RoleService 构造；两者的发布、调用和用户生命周期应保持上游规定的顺序。

## 6. 无硬件设备如何满足契约

最小设备可以没有 SIM、摄像头、GPS、蓝牙、指纹、NFC、UWB、打印、电视、车载、VR、折叠屏、NPU、同步客户端及相关 UI 应用。处理层次应是：

1. 实际产品不声明不存在的 hardware/software feature，关闭对应资源/flag、设置入口和 SystemUI 可选功能。
2. 共享 Framework 服务仍按标准提供 API，允许上游已支持的空设备/不可用返回。
3. 对启动路径确实依赖 HAL 的端点，提供适合本 QEMU 的 AOSP 软件实现或很小的 Kiki 虚拟实现，配齐 VINTF、init、权限与配置。不能声明了实例却启动后 stop。
4. 没有上游可缺省路径时，在设备侧建立明确的适配，不能又扩散为 Framework 吞异常。

本次源码中已找到可复用模块定义：

| 用途 | 实际存在的候选 | 使用边界 |
| --- | --- | --- |
| 软件 KeyMint | `android.hardware.security.keymint-service.nonsecure` | 测试设备凭据后端；需核查匹配的实例、配置和初始化，不是硬件安全实现 |
| 软件 GateKeeper | `android.hardware.gatekeeper-service.nonsecure` 或 Rust 对应实现 | 选择一种匹配后端，连同 gatekeeperd 验证 |
| Power | `android.hardware.power-service.example` | 按虚拟设备能力返回，不能挂起宿主 |
| Health | `android.hardware.health-service.example` | 需确认无真实电池时仍及时上报有效的外接电源/电池状态 |
| Sensors | `android.hardware.sensors-service.example` 的接口实现可参考 | 不能假设示例默认就是空传感器；本设备要求稳定的无传感器语义，且不依赖 goldfish qemud |
| Audio | `android.hardware.audio.service-aidl.example` 及其 effect 对应实现 | 需核对 policy/端口/设备配置；服务能注册不等于宿主已能听到音频 |

这些是**已确认源码存在的候选**，尚未为 Kiki 测试通过。不会照搬需要 Cuttlefish vsock 或 goldfish 专有宿主协议的后端。图形继续使用我们已验证的适配，不因 Framework 恢复换显示方案。

VINTF 将系统/设备/模块的 HAL 声明组合起来，设备树可以提供对应 fragments；恢复时必须检查最终组合结果，而不是仅在 PRODUCT_PACKAGES 追加名称。[官方 VINTF 文档](https://source.android.com/docs/core/architecture/vintf/objects)

## 7. 一次性实施方案

### 第一步：冻结现状和划分补丁

固定上述 manifest 与各仓库 revision，保存现有基线镜像及哈希、当前补丁和 v106 未验证构建状态。按以下类别审查现有补丁：

- 保留已验证的平台适配：Windows ARM QEMU 启动、内核/DRM/HWC/allocator 路径、ARM64-only、必要 mount namespace 处理和已确认的运行库修复。
- 撤销/替换启动裁剪：minimal-services shortcut、phase 白名单、吞初始化异常、bootstrap/fail-open 路径，以及下层对恢复服务的 stop/伪 ready。
- 诊断日志单独控制，避免高频串口输出影响运行。

**不能只设置 `ro.kikiaosp.minimal_services=false`**：还有独立的 battery/watchdog/telephony_registry 等属性门控、init stop 规则、native/APEX/package 配置需要一起恢复。

### 第二步：恢复标准启动图，精简由设备产品表达

恢复同一上游 revision 的 SystemServer/SystemServiceManager 启动、就绪和用户回调语义。对其他类中为“缺服务”而加入的临时 guard 一并核查，保留有明确设备理由的适配，撤掉掩盖初始化失败的部分。

不为当前报错继续添加新的 startService 白名单。未额外关闭的上游默认服务及动态 APEX/设备服务按正常条件启动；选定 feature 的关闭必须连同调用方路径一起证实。

所有改动归档到 `kikiaosp_test` 中的设备文件或小型、可追踪补丁；AOSP 工作区只是由这些资产生成的构建树。保持原产品身份。

### 第三步：一次配齐 native 与虚拟硬件依赖

恢复与上述 Framework 对应的 native 启动：keystore2/GateKeeper/软件 KeyMint、netd/BPF/DNS、音频、电源/Health、Sensors 等。移除冲突的 running→stop 规则、伪造 module-hash ready 等绕过。

为所有实际启用端点核对：模块安装位置、init service、运行用户/权限、VINTF 实例、动态库/APEX namespace、数据目录和 feature/RRO。无硬件返回值必须合法且不导致等待不返回。

同时核对 rc4 内核配置能提供启用链需要的 Binder、cgroup/task profiles、SELinux 接口、文件系统/用户存储、BPF/网络与挂起接口；只有证据指出缺项才安排内核变更，不为了 Java 服务表直接重编内核。

### 第四步：构建前完成静态验收，再做一次整合构建

构建前的准入条件：

- 对照调用点清单逐项确认：跟随上游、被哪个原版条件关闭、或由哪个有依据的设备适配处理；动态服务也要核查实际资源/APEX 列表。
- 100/200/480/500/520/550/600/1000 的生命周期及显式 ready 路径齐全。
- 要启用的 API 没有“仅构造 Manager、无后端/无 onBootPhase”的情况。
- init 中没有对这些端点的冲突 stop 或被遗忘的 disabled 触发问题。
- 以构建系统解析后的 APK/APEX/features/VINTF/资源列表为准；检查继承后的过滤结果，不只看 mk 表面。
- Settings、SettingsProvider、Launcher、SystemUI、PermissionController、测试 APK 及正常系统支持组件完整；不另行添加拨号/短信/相机等应用。
- 标准 RRO/OverlayManager 生效，关闭可选能力时使用真实生效的资源。[RRO 文档](https://source.android.com/docs/core/runtime/rros)

然后在 185 的 tmux 中做**同一产品的增量构建并重新生成一致的分区镜像**，复用已有编译缓存，不执行 clean/mrproper。这次涉及 native/HAL/init/资源，不能只替换 services.jar 就宣称完成；完整打包也不等于从头重编所有目标。传输后逐分区校验哈希。

### 第五步：本地统一验收

在 Windows ARM 本机测试，QEMU 最大化并置前：

1. 没有伪 ready；Framework 正常到达启动完成，用户 0 到达目标解锁状态，ADB 稳定。
2. system_server、SurfaceFlinger、SystemUI 没有循环重启；检查首次异常，而不把后续 DeadSystem 当新根因。
3. Launcher 可见；`am start -W` 启动测试 APK 后得到真实前台 Activity 与窗口。
4. TEST OK 和关闭按钮可见，取得至少两帧内容不同的 Windows 桌面截图，并以窗口/SurfaceFlinger 信息核对来源。
5. 关闭按钮结束 Activity 返回 Launcher；Settings 主界面可打开；状态栏/通知栏可展开并显示测试通知。
6. 持续至少 30 分钟检查核心进程、内存和崩溃记录；完成后及时关闭 QEMU。

Settings 每个硬件专属页面、完整音频体验、高刷与长期兼容不是这一轮全部验收目标；不得以缺乏实际硬件为由让主界面启动时异常。

## 8. 结果边界与决策

这套方案解决的是“依赖关系被裁断，因此每次运行才发现下一个服务”的结构性问题。主线内核与软件 HAL 的实际行为仍需整合验收，不能承诺源码表列全就一定一镜成功。

本轮停留在调研、清单和方案归档；没有实施整体恢复、没有启动 v106 QEMU。建议下一次实施以整套 Framework/native/设备契约为单位推进，保留精简应用目标，不再用单个异常推动逐项服务补丁。
