# Xiaomi USB DAC Rate Follower

## 中文

面向 Xiaomi 17 Ultra Android 17 的 USB DAC 自适应采样率模块。指定播放器
通过系统原生 `hifi_playback` 路径输出，采样率可随音轨在 44.1、48、88.2、
96、176.4、192 和 384 kHz 之间切换。

### 适配范围

- 设备：Xiaomi 17 Ultra（`nezha`）
- 系统：Android 17 / API 37
- 固件：`OS4.0.0.15.XPACNXM`
- 播放器：Apple Music、网易云音乐
- 输出：USB Audio
- Root：Magisk，或带有效 metamodule 的 KernelSU

扬声器、蓝牙、模拟耳机和混合输出不会被模块修改。安装器会验证设备指纹、
ELF 架构、关键代码上下文和补丁位置。不匹配时会终止安装。

### 特性

- 使用 Xiaomi 原生 `HifiSampleRateManager` 处理播放状态和采样率切换
- 为 Qualcomm USB 音频路径补充 44.1 kHz 能力
- 同步 AudioFlinger、AIDL HAL、PAL 和 USB 输出采样率
- 修正 HIFI 输出的初始 PCM32/48 kHz 配置
- 最后一个 HIFI 音轨停止后恢复普通 48 kHz 状态
- 无常驻守护进程、轮询、Zygisk 或应用 Hook

### 限制

输出目标：采样率跟随。严格 Bit Perfect 不在本项目保证范围内。

本模块仅适用于上述设备和固件。

### 构建

```sh
ANDROID_NDK_HOME=/path/to/android-ndk bash scripts/build.sh
```

构建产物位于 `dist/`。

### 适配其他设备

请在 Issue 中提供以下信息：

- 设备、系统、完整指纹、SDK、平台和 Root 方案
- `libaudiopolicymanagerdefault.so`
- `libaudiopolicycomponents.so`
- `libaudioflinger.so`
- `libaudiopolicymanagerimpl.so` 及相关 stub 库
- Qualcomm USB 音频库和 AIDL HAL
- 音频 policy、VINTF manifest 和 init RC
- USB DAC 连接并播放时的 AudioPolicy、AudioFlinger、ALSA 和 USB 状态
- 44.1、48、96 kHz 切换及停止、重连过程的日志
- DAC 型号和数显采样率

上传前请删除个人信息。每个设备和固件都需要单独适配。

## English

An adaptive sample-rate module for USB DAC playback on the Xiaomi 17 Ultra
running Android 17. Supported players use the native `hifi_playback` path and
can follow tracks between 44.1, 48, 88.2, 96, 176.4, 192 and 384 kHz.

### Supported target

- Device: Xiaomi 17 Ultra (`nezha`)
- OS: Android 17 / API 37
- Firmware: `OS4.0.0.15.XPACNXM`
- Players: Apple Music and NetEase Cloud Music
- Output: USB Audio
- Root: Magisk or KernelSU with an active metamodule

Speaker, Bluetooth, analogue and mixed routes are left untouched. The
installer validates the build fingerprint, ELF architecture, code context and
patch locations, and aborts on a mismatch.

### Features

- Uses Xiaomi's native `HifiSampleRateManager`
- Adds 44.1 kHz support to the Qualcomm USB audio path
- Keeps AudioFlinger, the AIDL HAL, PAL and USB output synchronized
- Starts HIFI playback with a coherent PCM32/48 kHz configuration
- Restores the normal 48 kHz state after the final HIFI track stops
- No daemon, polling loop, Zygisk code or application hook

### Limitations

Output target: sample-rate following. Strict bit-perfect output is outside the
project's guarantee.

This module is limited to the device and firmware listed above.

### Build

```sh
ANDROID_NDK_HOME=/path/to/android-ndk bash scripts/build.sh
```

Build artifacts are written to `dist/`.

### Porting requests

Open an Issue with the device and firmware details, complete build fingerprint,
Root setup, policy and audio libraries, Qualcomm USB and AIDL HAL libraries,
active audio configuration files, AudioPolicy and AudioFlinger dumps, ALSA and
USB state, transition logs for 44.1/48/96 kHz and stop/reconnect events, and the
DAC model. Remove personal information before uploading. Each device and
firmware requires separate adaptation.
