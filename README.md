# Xiaomi USB DAC Rate Follower

## 中文

### 项目简介

在 MIUI 时代，小米曾短暂为小米 9 至小米 11 的部分设备适配自适应
采样率切换，也就是通常所说的“绕过 Android SRC”。系统底层为此实现了
独立的 `HifiSampleRateManager`。

随着后续设备不再完整适配这项功能，同时高通音频底层由 HIDL 迁移至
AIDL HAL，原有功能只留下了一套未完成适配的历史代码。在本项目测试的
小米 17 Ultra Android 17 固件中，`hifi_playback` 会以 384 kHz 动态配置
创建；普通 44.1/48 kHz 音轨不会正常进入该通道，而进入后又容易锁在首次
播放曲目的采样率。残留实现的实际灵活性甚至不如完全禁用它。

本模块用于修正并补齐这套原生 HIFI 链路，使指定播放器在连接 USB DAC
时进入 `hifi_playback`，并由小米已有的 `HifiSampleRateManager` 随音轨在
44.1、48、88.2、96 kHz 等采样率之间切换。它不使用常驻守护进程、轮询、
Zygisk 或应用内 Hook。

> 这是针对特定固件的实验性采样率跟随模块，不是严格 Bit Perfect 声明。

### 当前适配范围

- 设备：Xiaomi 17 Ultra（`nezha`）
- 系统：Android 17 / API 37
- 固件：`OS4.0.0.15.XPACNXM`
- 播放器：Apple Music、网易云音乐
- 输出：仅 USB Audio；扬声器、蓝牙、模拟耳机和混合路由不介入
- Root：Magisk，或启用了 metamodule（建议 `meta-overlayfs`）的 KernelSU

安装器会核对完整系统指纹、ELF 架构、关键函数上下文、对象布局和每个补丁
位置。其他设备或固件会直接终止安装。

### 修正内容

1. 在系统完成原有输出选择后，仅当目标包名和当前路由都满足条件时，将
   最终输出指向已存在的 `hifi_playback`。
2. 将 44.1 kHz 加入高通 USB 助手实际返回的七个采样率，同时保留
   352.8 kHz。
3. 让 AudioFlinger 在 44.1/48 kHz 边界也重新读取 HAL 已接受的采样率，
   避免 DAC 时钟已改变而 MixerThread 状态未更新。
4. 允许高通 AIDL HAL 的 HIFI usecase 进入原有 PAL 设备重配置路径。
5. 在动态 profile 完成 USB 能力查询后，仅将 `hifi_playback` 的初始打开
   配置设为 PCM32/48 kHz。MixerThread、AIDL FMQ 与 PAL 因而从同一个
   48 kHz 状态创建，QTI 原生 40 ms 计算会得到 1920 帧；后续切换继续由
   小米原生链路统一更新 Mixer 与 HAL。
6. 最后一个 HIFI 音轨释放后，以小米自己的应用计数为准，忽略仍残留在
   LATEST_MAX 树中的合成 384 kHz 节点，将共享 USB 后端恢复至普通应用
   使用的 48 kHz。

所有运行时扫描都有固定上限。遇到空路由、未知设备、过期输出、混合路由
或异常对象时，模块保持系统原选择，不发送采样率命令。

### 网易云切歌第一秒异常

关闭网易云音乐的“淡入淡出”只会关闭应用自己的效果。切歌时网易云仍会
销毁并重建主 `AudioTrack`，AudioFlinger 也会对旧轨执行系统级保护淡出。
这部分不是应用设置能够关闭的。

HIFI 输出原本会以 384 kHz 创建，随后只改变 HAL 媒体配置；AIDL 共享缓冲
却仍保留 15360 帧。模块让该输出从 48 kHz/1920 帧的一致初态创建，并在
后续采样率事件中让 AudioFlinger 重读 HAL 状态、重建 AudioMixer。它保留
系统的防爆音淡出，只修正底层缓冲和采样率状态不一致的问题。

### PCM 与 Bit Perfect

当前验证链路是 PCM32 USB MixerThread。模块的目标是让输出采样率跟随音源，
不会承诺源数据逐 bit 不变。以下情况仍可能破坏严格 Bit Perfect：

- 播放器自身 DSP、均衡器、音量标准化或淡入淡出；
- Android 软件音量和系统音效；
- PCM16、PCM24、Float 与 PCM32 之间的格式转换；
- 多个应用或系统声音同时播放。

仅声明 `AUDIO_OUTPUT_FLAG_BIT_PERFECT` 也不能解决本固件普通 44.1/48 kHz
音轨被选到 Deep Buffer、USB 能力列表缺少 44.1 kHz，以及 HIFI 固定缓冲
失配的问题。

### 构建

```sh
ANDROID_NDK_HOME=/path/to/android-ndk bash scripts/build.sh
```

构建流程会生成无动态重定位的 AArch64 补丁，检查机器码、大小与安装脚本，
运行路由安全模型，并在 `dist/` 生成可复现的 Magisk/KernelSU ZIP。

### 为其他设备请求适配

请勿在其他机型或固件上强行安装。提交 Issue 时请附上：

- 系统与 vendor 指纹、SDK、设备代号、平台、Root 方案和 metamodule；
- `/system/lib64/libaudiopolicymanagerdefault.so`；
- `/system/lib64/libaudiopolicycomponents.so`；
- `/system/lib64/libaudioflinger.so`；
- `/system_ext/lib64/libaudiopolicymanagerimpl.so` 及其 stub 库；
- `/vendor/lib64/libdev_usb.so` 和当前 QTI AIDL 音频 HAL；
- 正在使用的 audio policy/module XML、VINTF manifest 与音频 init RC；
- USB DAC 接入并播放时的 `dumpsys media.audio_policy`、
  `dumpsys media.audio_flinger`、ALSA card/PCM 和 USB `stream0`；
- 覆盖 44.1 → 48 → 96 → 44.1、完全停止及重新连接的日志，以及 DAC 型号
  和数显采样率。

上传前请删除与问题无关的个人信息。每个固件都需要重新核对偏移和结构。

---

## English

### Introduction

During the MIUI era, Xiaomi briefly shipped adaptive sample-rate switching on
some devices from the Mi 9 through Mi 11. This is commonly described as
bypassing Android SRC, and Xiaomi implemented a dedicated
`HifiSampleRateManager` for it.

Later devices stopped receiving a complete adaptation while Qualcomm migrated
its audio stack from HIDL to the AIDL HAL. What remains is an unfinished legacy
path. On the Xiaomi 17 Ultra Android 17 firmware tested by this project,
`hifi_playback` is created from a 384 kHz dynamic configuration; ordinary
44.1/48 kHz tracks do not enter it correctly, and tracks that do enter can stay
locked to the first song's rate. In practice, the leftover implementation can
be less flexible than disabling it entirely.

This module repairs and completes that native HIFI path. When a USB DAC is
selected, specified players are routed to `hifi_playback`, and Xiaomi's own
`HifiSampleRateManager` follows tracks across 44.1, 48, 88.2, 96 kHz and other
supported rates. It uses no resident daemon, polling loop, Zygisk code, or
in-app hook.

> This is a firmware-pinned experimental rate-following module, not a strict
> bit-perfect claim.

### Supported target

- Device: Xiaomi 17 Ultra (`nezha`)
- OS: Android 17 / API 37
- Firmware: `OS4.0.0.15.XPACNXM`
- Players: Apple Music and NetEase Cloud Music
- Route: USB Audio only; speaker, Bluetooth, analogue and mixed routes are
  left untouched
- Root: Magisk, or KernelSU with an active metamodule such as `meta-overlayfs`

The installer validates the full build fingerprint, ELF architecture, local
function context, object layouts and every patch location. Any other device or
firmware is rejected.

### What it fixes

1. After the stock output decision, the final handle is redirected to the
   existing `hifi_playback` output only for an allowed package on a USB-only
   route.
2. 44.1 kHz is placed inside Qualcomm's seven returned USB rates while
   retaining 352.8 kHz.
3. AudioFlinger rereads an accepted HAL rate at the 44.1/48 kHz boundary, so
   its MixerThread does not remain stale after the DAC clock changes.
4. The QTI AIDL HIFI usecase is admitted to the existing PAL device
   reconfiguration path.
5. After dynamic USB capability discovery, only `hifi_playback` is initially
   opened as PCM32/48 kHz. MixerThread, the AIDL FMQ and PAL therefore start
   from one coherent state, and QTI's stock 40 ms calculation creates 1920
   frames. Xiaomi's native path updates Mixer and HAL together afterward.
6. When the final HIFI track is released, Xiaomi's own application count is
   authoritative. A retained synthetic 384 kHz LATEST_MAX node is ignored and
   the shared USB backend returns to the normal 48 kHz mixer rate.

All runtime scans are bounded. Empty, stale, unknown, mixed or non-USB routes
fail closed and keep the system's original output decision.

### NetEase first-second glitches

Disabling NetEase crossfade disables only the app's own effect. NetEase still
destroys and recreates its main `AudioTrack` at a song boundary, while
AudioFlinger applies a protective system fade to the old track.

The HIFI output originally started at 384 kHz and later changed only the HAL
media configuration, leaving a 15360-frame AIDL queue behind. This module
creates the output from a coherent 48 kHz/1920-frame state and makes
AudioFlinger reread the accepted HAL state and rebuild AudioMixer on later rate
events. Android's anti-pop fade remains intact.

### PCM and bit perfect

The verified route is a PCM32 USB MixerThread. The module follows source sample
rates but does not promise bit-identical samples. Player DSP, software volume,
effects, PCM/Float format conversion and concurrent playback can still prevent
strict bit-perfect output.

Declaring `AUDIO_OUTPUT_FLAG_BIT_PERFECT` alone does not fix this firmware's
low-rate Deep Buffer selection, missing 44.1 kHz USB capability, or immutable
HIFI-buffer mismatch.

### Build

```sh
ANDROID_NDK_HOME=/path/to/android-ndk bash scripts/build.sh
```

The build produces relocation-free AArch64 blobs, validates instruction bytes,
sizes and installer logic, runs fail-closed routing models, and creates a
reproducible Magisk/KernelSU ZIP in `dist/`.

### Requesting another-device port

Do not force-install this ZIP on another device or firmware. Open an Issue with
the build/vendor fingerprints, SDK, device/platform and root setup; the policy,
AudioFlinger, QTI USB and AIDL HAL libraries listed in the Chinese section;
active audio XML/VINTF/init files; AudioPolicy and AudioFlinger dumps; ALSA and
USB descriptors; and logs covering 44.1 → 48 → 96 → 44.1, full stop and USB
reconnection. Remove unrelated personal information before uploading.
