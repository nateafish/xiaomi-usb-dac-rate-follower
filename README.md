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

请不要直接安装现有 ZIP。先在设备连接并获得 root 后，在仓库根目录运行：

```sh
bash scripts/collect_device_port.sh
```

脚本只读采集并生成 `xiaomi-usb-dac-port-*.tar.gz`。检查并删除个人信息
后，将压缩包附在 Issue 中。也可以手工提供以下内容。

#### 必需的系统信息

- 设备型号、`ro.product.device`、Android 版本、SDK、SoC/平台和完整
  `ro.build.fingerprint`
- Magisk 或 KernelSU 版本；KernelSU 还要说明 metamodule/overlay 方案
- 已安装的音频相关模块、音效、厂商增强功能，以及是否启用 Dolby、DTS
  或其他处理链
- DAC 型号、USB 连接方式、DAC 数显结果和实际测试音轨的 PCM 格式

#### 必需的 ELF 文件

这些是当前模块直接分析或改写的核心对象，必须从目标设备原路径导出，
保持原始文件名和完整文件内容：

- `libaudiopolicymanagerdefault.so`
- `libaudiopolicycomponents.so`
- `libaudioflinger.so`
- `libaudiopolicymanagerimpl.so` 及同目录的 stub/接口库
- `libaudioclient.so`、`libaudiopolicyservice.so`（如果存在）
- `libdev_usb.so`
- `libaudioplatformconverter.qti.so`（如果存在）
- 当前 Qualcomm Audio HAL：`libaudiocorehal.qti.so`、`libaudiocorehal.default.so`
  或同类 `audio.*` / `android.hardware.audio*` 库
- 实际注册音频服务的可执行文件，例如 `audiohalservice.qti`，以及
  `audioserver` 的 `/proc/<pid>/maps` 中出现的音频相关库

#### HIDL 对照所需文件

如果设备仍提供 HIDL，除了上面的通用对象，还要提供实际存在的全部相关
文件，而不是只给文件名：

- `vendor/lib64/hw/audio.primary*.so`
- `vendor/lib64/hw/audio.usb*.so`、`audio.bluetooth*.so`
- `vendor/lib64/hw/android.hardware.audio@*.so`、
  `android.hardware.audio.effect@*.so`
- `vendor/bin/hw/android.hardware.audio@*.service` 或同类 audio HAL 服务
- 同一服务进程的 `/proc/<pid>/maps`，以及依赖的 Qualcomm `libpal`、`libagm`、
  `libacdb`、`libqahw`、tinyalsa、平台 converter 和 USB 库
- HIDL 版本的 VINTF manifest、init RC 和 audio HAL 配置

旧设备还要保留实际服务使用的 ABI：如果 HAL 进程加载 `/vendor/lib/`，请同时
提供 32 位库；不能只导出同名的 `/vendor/lib64/` 文件。

#### 配置和运行状态

- 当前生效的 audio policy/module XML、audio policy engine XML、厂商 audio
  interface XML，以及相关 SKU/ODM 覆盖文件
- audio HAL 的 VINTF manifest 和 init RC
- `dumpsys media.audio_policy`
- `dumpsys media.audio_flinger`
- `/proc/asound/cards`、`/proc/asound/pcm`、相关 `card*/stream*`，以及 USB
  描述符或 `dumpsys usb`
- `service list`、音频服务进程列表和 audio 服务的 SELinux 上下文

#### 必需的动态日志

请清理日志后，在 DAC 已连接时依次测试 44.1、48、96、44.1 kHz，完全停止
播放，再拔插 DAC。日志要覆盖每个切换前后至少数秒，并同时记录 DAC 数显。
至少包含 `AudioPolicy`、`AudioFlinger`、AIDL/HIDL HAL、PAL/AGM、ALSA、USB
和采样率关键字。不要上传 APK、歌曲文件或与音频问题无关的完整 logcat。

各设备和各固件需要单独核对 ELF 架构、代码上下文、版本和补丁位置。只有
拿到对应的 stock 库，才能判断旧 HIDL 路径是否存在可迁移的实现。

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

Do not install an existing ZIP on an unlisted device. With adb and root
available, run `bash scripts/collect_device_port.sh` from the repository root.
It creates a read-only `xiaomi-usb-dac-port-*.tar.gz` containing device
metadata, relevant ELF files, AIDL/HIDL discovery data, active configuration,
audio state, ALSA/USB state, and filtered recent logcat. Review and remove
personal information before attaching it to an Issue.

The archive must include the stock versions of the libraries at their original
paths. The current patch targets are `libaudiopolicymanagerdefault.so`,
`libaudioflinger.so`, `libdev_usb.so`, and the Qualcomm Audio HAL. The policy
components and Xiaomi policy implementation libraries are required for layout
analysis even though this module does not overwrite them. For a HIDL device,
also include every existing `audio.primary*.so`, `audio.usb*.so`,
`audio.bluetooth*.so`, `android.hardware.audio@*.so`, matching HAL service
binaries, and the audio-related libraries shown in the service process maps.

Include active audio policy/module XML, policy-engine XML, VINTF manifests,
audio init RC files, AudioPolicy and AudioFlinger dumps, ALSA and USB state,
and logs covering 44.1 -> 48 -> 96 -> 44.1 kHz, stop, and DAC reconnect. State
the DAC model, displayed rate, PCM format, effects/Dolby status, and observed
result. Do not upload APKs, music, or unrelated full logcat. Every device and
firmware needs a separate signature and offset review.
