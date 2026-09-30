# KikiAOSP Surface Camera HAL

设备树内的 AIDL Camera provider，使用上游 Goldfish 的会话/元数据框架，但真实像素来自本地主仓库的 Windows ARM64 Surface camera bridge；不发布合成相机。前后摄为设备 0/1，640×480 NV12，经 `org.kikiaosp.camera` virtio-serial channel 传输。

Windows 帧已正向，两个设备的 `SENSOR_ORIENTATION` 均为 0；不根据虚拟手机窗口形状套用 270 度。OPEN 会释放上一摄像头，CLOSE 必须在宿主释放实际 reader/source 后返回 CLOSED，设备 HAL 使用这项确认避免抢占尚未关闭的另一传感器。

CP2A 目标为 `kikiaosp_test_arm64_phone-cp2a-userdebug`。更新本目录之后同步设备树；只改 HAL/gralloc 时运行 `m -j8 vendorimage`，不应全量重编系统。

```bash
cd ~/projects/kikiaosp_test
./scripts/sync-device-tree.sh ~/aosp-master
./scripts/audit-aosp-integration.sh ~/aosp-master
cd ~/aosp-master
source build/envsetup.sh
lunch kikiaosp_test_arm64_phone-cp2a-userdebug
m -j8 vendorimage
```

首次从干净上游源码准备时，还需按仓库主 README 应用完整集成补丁：camera source-filegroup patch、`aosp-kikiaosp-virgl-context-before-prime.patch`、`aosp-kikiaosp-virgl-cpu-camera-yuv.patch` 都由 apply/audit 脚本管理，不能留为 AOSP 外的手工修改。

两个 gralloc 修复分别解决 PRIME import 前缺失 VirGL context、CPU YUV ImageReader 组合不支持。后者沿用现有 R8 emulation，不声称 Windows 原生支持 NV12 GPU 纹理。上游 gfxstream、GBM 和 2D 路径不因该功能改为软件渲染。

2026-09-30 回归：稳定 SDL QEMU SHA-256 `5b92d13e421124d55e0420d3879cabdc491eeb3cf370332ec4bc84a57e4ff49a`；显示仍为 VirGL ES3.1、1003×1556、120Hz、8 vCPU / 4GiB。用户确认拍摄恢复；`Pictures` JPEG 在本机解码为640×480。相机 checkpoint vendor 为 `115626c3ad9a31744389307e135e8a6a08922749ec1e02cf5f3b3d3cb2848350`；加入完整 ThemePicker 后的已验收主线 vendor 为 `72202a6af84fc79fc35cefb6d0f6e502fc266b2bbc6c867a49271f4dd234bb4a`，完整配对以主仓库 `profiles/surface-main-20260930.json` 为准。

相机预览使用已有 GPU 合成/显示加速；采集/传输/部分转换及 JPEG 编码仍在 CPU。视频录制、硬件 JPEG 编码、零拷贝尚未验收。Windows 桥接源码、构建、启动器和完整镜像配对属于本地主仓库，其 CAMERA_SUPPORT.md 保存详细回溯说明。真实相机照片、桌面截图及构建日志不进入 Git。
