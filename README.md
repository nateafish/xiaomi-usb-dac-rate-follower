# Xiaomi USB DAC Rate Follower

## 中文

面向 Xiaomi 17 系列 Qualcomm AIDL 音频栈的 USB DAC 自适应采样率模块。
当前实机目标为 Xiaomi 17 Ultra Android 17；指定播放器通过系统原生
`hifi_playback` 路径输出，采样率可随音轨在 44.1、48、88.2、96、176.4、
192 和 384 kHz 之间切换。

### 适配范围

| 机型 | 代号 | 系统 / 固件基线 | 验证状态 | 模块状态 | 适配类型 |
| --- | --- | --- | --- | --- | --- |
| Xiaomi 17 Ultra | `nezha` | Android 17 / API 37<br>`OS4.0.0.15.XPACNXM` | **实机验证** | 可安装 | 原生 HIFI 修复 |
| Xiaomi 17 Ultra | `nezha` | Android 16 / API 36<br>`OS3.0.309.0.WPACNXM` | **理论适配（OTA 离线）** | 可安装（安装时提示） | 原生 HIFI 移植 |
| Xiaomi 17 | `pudding` | Android 16 / API 36<br>`OS3.0.315.0.WPCCNXM` | **理论适配（OTA 离线）** | 可安装（安装时提示） | AIDL HAL 移植 |
| Xiaomi 17 Pro Max | `popsicle` | Android 16 / API 36<br>`OS3.0.318.0.WPBCNXM` | **理论适配（OTA 离线）** | 可安装（安装时提示） | AIDL HAL 移植 |

“实机验证”表示已在设备、USB DAC 和实际播放器上测试；“理论适配”表示已从
完整 OTA 提取目标库，并通过语义注入、分支重定位和两次应用幂等验证，但没有
对应实机。理论适配不等于已经确认音频稳定性或严格 Bit Perfect。
安装理论适配目标时，安装器会显示醒目警告；按任一音量键确认后才会继续。

当前实机验证播放器为 Apple Music、网易云音乐，输出为 USB Audio。Root 支持
Magisk，或带有效 metamodule 的 KernelSU。

扬声器、蓝牙、模拟耳机和混合输出不会被模块修改。其他 Qualcomm Android 17
AIDL 音频基线会显示未验证警告，并且只有在 ELF 架构、唯一代码签名、对象布局
和补丁空间全部吻合时才允许继续；指纹和整库哈希仅用于诊断。

### 特性

- 使用 Xiaomi 原生 `HifiSampleRateManager` 处理播放状态和采样率切换
- 为 Qualcomm USB 音频路径补充 44.1 kHz 能力
- 同步 AudioFlinger、AIDL HAL、PAL 和 USB 输出采样率
- 修正 HIFI 输出的初始 PCM32/48 kHz 配置
- 最后一个 HIFI 音轨停止时，空闲 DAC 保持最后采样率直到 standby
- 普通 USB 输出已活动时，按实际接管状态恢复 48 kHz
- 无常驻守护进程、轮询、Zygisk 或应用 Hook

### 限制

输出目标：采样率跟随。严格 Bit Perfect 不在本项目保证范围内。

同一 Android 大版本内升级 system、vendor、odm 或 product 后，模块保持启用。
下次覆盖安装时，安装器会提示固件发生变化并重新执行全部结构检查。跨 Android
大版本或设备/HAL 目标发生变化时会中止安装。模块升级优先使用 Magisk 分区镜像；
KernelSU 使用当前模块 payload 作为升级基线，不在模块中保存整套 stock SO。

### 已验证基线

`v0.7.8-alpha` 已在 iBasso DC-Tonfa 上验证网易云音乐 44.1 kHz
HIFI 输出：AudioFlinger、PCM32 HAL 和 PAL 均运行于 44.1 kHz。暂停最后一个
HIFI 音轨后，不会先发送 48 或 384 kHz；线程保持 44.1 kHz 并直接进入
standby，内部空闲标记不会送入 HAL。

### 构建

```sh
ANDROID_NDK_HOME=/path/to/android-ndk bash scripts/build.sh
```

构建产物位于 `dist/`。

### 目标与智能匹配

仓库按 Android 大版本组织目标。`baselines/` 记录设备、SoC、board platform、
AIDL/HIDL 世代和接口版本，`usecases/` 保存对应的修改方案。安装器先选择候选方案，
再用函数局部签名、动态符号、PLT、对象布局和可执行空洞逐项确认。文件位置和
AArch64 分支在安装时重新计算，研究阶段记录的偏移不作为写入地址。

未记录的 Qualcomm 设备在 Android/HAL 基线相符时会显示警告，然后执行相同的
结构检查。零命中、多命中、未知布局或混合补丁状态都会中止。三个 Android 16
基线已通过 OTA 库的离线注入和两次应用幂等验证，现允许在确认“尚未实机验证”
警告后安装；该提示不代表稳定性或严格 Bit Perfect 已经得到验证。

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

新设备和新 Android/HAL 基线仍需提供 stock 库以验证语义签名与对象布局；不再
要求为每个固件手工维护一组裸偏移。旧 HIDL 路径必须按独立 use case 分析。

## English

An adaptive USB DAC sample-rate module for the Qualcomm AIDL audio stack used
by the Xiaomi 17 family. The current hardware-verified target is Xiaomi 17
Ultra on Android 17. Supported players use the native `hifi_playback` path and
can follow tracks between 44.1, 48, 88.2, 96, 176.4, 192 and 384 kHz.

### Compatibility status

| Model | Codename | OS / firmware baseline | Validation | Module status | Adaptation type |
| --- | --- | --- | --- | --- | --- |
| Xiaomi 17 Ultra | `nezha` | Android 17 / API 37<br>`OS4.0.0.15.XPACNXM` | **Hardware verified** | Installable | Native HIFI fix |
| Xiaomi 17 Ultra | `nezha` | Android 16 / API 36<br>`OS3.0.309.0.WPACNXM` | **Theoretical (offline OTA)** | Installable with warning | Native HIFI port |
| Xiaomi 17 | `pudding` | Android 16 / API 36<br>`OS3.0.315.0.WPCCNXM` | **Theoretical (offline OTA)** | Installable with warning | AIDL HAL port |
| Xiaomi 17 Pro Max | `popsicle` | Android 16 / API 36<br>`OS3.0.318.0.WPBCNXM` | **Theoretical (offline OTA)** | Installable with warning | AIDL HAL port |

“Hardware verified” means testing on the device with a USB DAC and real
players. “Theoretical” means the complete OTA was extracted and passed
semantic injection, branch relocation and two-pass idempotence checks without
corresponding hardware. It does not confirm runtime stability or strict
bit-perfect output.
For a theoretical target, the installer shows a prominent warning and waits
for either volume key before continuing.

Hardware testing currently covers Apple Music and NetEase Cloud Music over
USB Audio. Root support is Magisk or KernelSU with an active metamodule.

Speaker, Bluetooth, analogue and mixed routes are left untouched. Other
Qualcomm Android 17 AIDL audio baselines receive an unverified warning and may
continue only when the ELF architecture, unique code signatures, object
layouts and executable patch space all match. Fingerprints and whole-file
hashes are diagnostic only.

### Features

- Uses Xiaomi's native `HifiSampleRateManager`
- Adds 44.1 kHz support to the Qualcomm USB audio path
- Keeps AudioFlinger, the AIDL HAL, PAL and USB output synchronized
- Starts HIFI playback with a coherent PCM32/48 kHz configuration
- Keeps an idle DAC at the final source rate until HIFI standby
- Restores 48 kHz when an active ordinary USB output takes ownership
- No daemon, polling loop, Zygisk code or application hook

### Limitations

Output target: sample-rate following. Strict bit-perfect output is outside the
project's guarantee.

A system, vendor, ODM or product update within the same Android major version
does not disable the module. The next in-place module installation warns that
the firmware changed and repeats every structural check. A different Android
major version or device/HAL target is blocked. Module updates prefer Magisk's
partition mirror; KernelSU uses the active module payload as its upgrade base.
Full stock libraries are not duplicated inside the module.

### Verified baseline

`v0.7.8-alpha` was verified with NetEase Cloud Music and an iBasso DC-Tonfa
at 44.1 kHz. AudioFlinger, the PCM32 HAL and PAL all ran at 44.1 kHz. Pausing
the final HIFI track entered standby at 44.1 kHz without an intermediate 48 or
384 kHz update, and the internal idle marker did not reach the HAL.

### Build

```sh
ANDROID_NDK_HOME=/path/to/android-ndk bash scripts/build.sh
```

Build artifacts are written to `dist/`.

### Targets and semantic matching

Targets are grouped by Android major version. `baselines/` records the device,
SoC, board platform, AIDL/HIDL generation and interface version, while
`usecases/` contains the corresponding patch plans. After selecting a
candidate, every write is checked against function-local signatures, dynamic
symbols, PLT entries, object layouts and executable caves. File locations and
AArch64 branches are resolved during installation; research offsets are never
used as write addresses.

An unrecorded Qualcomm device receives a prominent warning before the same
structural checks run. Zero or multiple matches, unknown layouts and mixed
patch states abort. All three Android 16 baselines passed offline injection and
two-pass idempotence checks against extracted OTA libraries. Installation is
now allowed after acknowledging that hardware validation is still missing;
this does not certify runtime stability or strict bit-perfect output.

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
result. Do not upload APKs, music, or unrelated full logcat. Every new baseline
still requires complete semantic and layout validation before it is verified.
