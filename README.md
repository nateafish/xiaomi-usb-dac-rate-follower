# Xiaomi USB DAC Rate Follower

## 中文

面向 Xiaomi / Redmi Qualcomm AIDL 音频栈的 USB DAC 自适应采样率模块。
当前实机目标为 Xiaomi 17 Ultra Android 17；指定播放器通过系统原生
`hifi_playback` 路径输出，采样率可随音轨在 44.1、48、88.2、96、176.4、
192 和 384 kHz 之间切换。

### 适配范围

| 机型 | 代号 | 系统 / 固件基线 | 验证状态 | 模块状态 | 适配类型 |
| --- | --- | --- | --- | --- | --- |
| Xiaomi 17 Ultra | `nezha` | Android 17 / API 37<br>`OS4.0.0.15.XPACNXM` | **实机验证** | 可安装 | 原生 HIFI 修复 |
| Xiaomi 17 Ultra | `nezha` | Android 16 / API 36<br>`OS3.0.309.0.WPACNXM` | **理论适配（OTA 离线）** | 可安装（安装时提示） | 原生 HIFI 移植 |
| Xiaomi 17 | `pudding` | Android 16 / API 36<br>`OS3.0.315.0.WPCCNXM` | **理论适配（OTA 离线）** | 可安装（安装时提示） | AIDL HAL 移植 |
| Xiaomi 17 Max | `byron` | Android 16 / API 36<br>`OS3.0.308.0.WAFCNXM` | **理论适配（OTA 离线）** | 可安装（安装时提示） | AIDL HAL 移植 |
| Xiaomi 17 Pro | `pandora` | Android 16 / API 36<br>`OS3.0.318.0.WBLCNXM` | **理论适配（OTA 离线）** | 可安装（安装时提示） | AIDL HAL 移植 |
| Xiaomi 17 Pro Max | `popsicle` | Android 16 / API 36<br>`OS3.0.318.0.WPBCNXM` | **理论适配（OTA 离线）** | 可安装（安装时提示） | AIDL HAL 移植 |
| Redmi K90 Pro Max | `myron` | Android 16 / API 36<br>`OS3.0.308.0.WPMCNXM` | **理论适配（OTA 离线）** | 可安装（安装时提示） | AIDL v3 / 独立偏移布局移植 |
| Xiaomi 15 | `dada` | Android 16 / API 36<br>`OS3.0.305.0.WOCCNXM` | **理论适配（OTA 离线）** | 可安装（安装时提示） | AIDL v2 / PAL 工作线程移植 |

“实机验证”表示已在设备、USB DAC 和实际播放器上测试；“理论适配”表示已从
完整 OTA 提取目标库，并通过语义注入、分支重定位和两次应用幂等验证，但没有
对应实机。理论适配不等于已经确认音频稳定性或严格 Bit Perfect。
安装理论适配目标时，安装器会显示醒目警告；按任一音量键确认后才会继续。

播放器白名单：

- Apple Music（`com.apple.android.music`）
- 网易云音乐（`com.netease.cloudmusic`）
- QQ 音乐（`com.tencent.qqmusic`）
- Spotify（`com.spotify.music`）

输出为 USB Audio。Root 支持 Magisk，或带有效 metamodule 的 KernelSU。

扬声器、蓝牙、模拟耳机和混合输出不会被模块修改。其他 Qualcomm Android 17
AIDL 音频基线会显示未验证警告，并且只有在 ELF 架构、唯一代码签名、对象布局
和补丁空间全部吻合时才允许继续。指纹、Build ID 和整库哈希只用于诊断，不代替
结构检查，也不单独阻止兼容 OTA。

### 特性

- 使用 Xiaomi 原生 `HifiSampleRateManager` 处理播放状态和采样率切换
- 为 Qualcomm USB 音频路径补充 44.1 kHz 能力
- 同步 AudioFlinger、AIDL HAL、PAL 和 USB 输出采样率
- 设置 HIFI 输出的初始值为 PCM32/48 kHz
- 最后一个 HIFI 音轨停止时，空闲 DAC 保持最后采样率直到 standby
- 普通 USB 输出已活动时，按实际接管状态恢复 48 kHz
- 无常驻守护进程、轮询、Zygisk 或应用 Hook

### 限制

输出目标：当前实现基于小米原有残留的 Hifi 输出通道，
而非安卓 14 后提供的 Bit Perfect 通道。

不支持模块覆盖升级。安装其他构建前必须删除现有模块并重启；
安装器检测到同 ID 的活动或残留模块目录时会直接中止。

模块在安装中注入系统 SO 修改，不保存整套 stock SO。

### 构建

```sh
ANDROID_NDK_HOME=/path/to/android-ndk bash scripts/build.sh
```

构建产物位于 `dist/`。

### 适配说明

仓库按 Android 大版本组织目标。`baselines/` 记录设备、SoC、board platform、
AIDL/HIDL 世代和接口版本，`usecases/` 保存对应的修改方案。安装器先选择候选方案，
再用函数局部签名、动态符号、PLT、对象布局和可执行空洞逐项确认。文件位置和
AArch64 分支在安装时重新计算，研究阶段记录的偏移不作为写入地址。

未记录的 Qualcomm 设备在 Android/HAL 基线相符时会显示警告，然后执行相同的
结构检查。零命中、多命中、未知布局或混合补丁状态都会中止。七个 Android 16
基线均已通过 OTA 库的离线注入和两次应用幂等验证，且允许在确认“尚未实机验证”
后安装。

### 适配其他设备

采集脚本把“全新适配”和“安装后排错”严格分开。两种压缩包不能互相替代。

#### 全新适配（尚未安装本模块）

请不要直接安装现有 ZIP。设备必须处于未安装本模块的原厂视图；如果以前安装过，
请完整卸载并重启。连接设备并获得 root 后，在仓库根目录运行：

```sh
bash scripts/collect_device_port.sh port --capture-transitions
```

`port` 会拒绝已安装或待更新的本模块，采集原厂 ELF、配置、服务映射和运行状态。
`--capture-transitions` 会引导测试 44.1、48、88.2、96、176.4、192、384 kHz，
再回到 44.1 kHz、停止播放并重新连接 DAC，同时为每一步保存 AudioPolicy、
AudioFlinger 和 ALSA 快照。如果暂时无法做动态测试，也可以只采集静态基线：

```sh
bash scripts/collect_device_port.sh port
```

#### 已安装后提交问题

如果设备已经安装本模块，需要报告不跟随、无声、卡顿、音频服务崩溃或其他异常，
请保留故障现场并运行：

```sh
bash scripts/collect_device_port.sh issue --capture-transitions
```

无法完成切换流程时运行 `bash scripts/collect_device_port.sh issue`。`issue` 模式
会采集已安装模块的版本、状态、覆盖文件、当前生效的目标库、音频状态及崩溃线索；
它不是原厂基线，不能用于全新适配。

两种模式都只读访问设备，不清空日志，不导出分区镜像、APK、音乐或应用私有目录。
默认只保留一个 `xiaomi-usb-dac-{port,issue}-*.tar.gz`，不会同时保留同体积的
解压目录。多设备连接时使用 `--serial SERIAL`；确实需要查看目录时使用
`--keep-directory`，只要目录而不要压缩包时使用 `--no-archive`。上传前请查看
压缩包内的 `PRIVACY-REVIEW.txt` 和 `state/collection-warnings.txt`，删除不希望
公开的信息。以下内容是全新适配所需材料，也可以手工提供。

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
- 当前 USB/PAL 实现，例如 `libdev_usb.so` 或 `libar-pal.so`
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

推荐使用 `port --capture-transitions`，在 DAC 已连接时依次测试 44.1、48、
88.2、96、176.4、192、384 kHz，再回到 44.1 kHz，完全停止播放并拔插 DAC。
日志要覆盖每个切换前后至少数秒，并同时记录 DAC 数显。
至少包含 `AudioPolicy`、`AudioFlinger`、AIDL/HIDL HAL、PAL/AGM、ALSA、USB
和采样率关键字。不要上传 APK、歌曲文件或与音频问题无关的完整 logcat。

新设备和新 Android/HAL 基线仍需提供 stock 库以验证语义签名与对象布局；不再
要求为每个固件手工维护一组裸偏移。旧 HIDL 路径必须按独立 use case 分析。

## English

An adaptive USB DAC sample-rate module for Xiaomi and Redmi devices using the
Qualcomm AIDL audio stack.

The current hardware target is Xiaomi 17 Ultra on Android 17. A specified player
outputs through the system native `hifi_playback` path, and the sample rate can
follow the track between 44.1, 48, 88.2, 96, 176.4, 192 and 384 kHz.

### Compatibility status

| Model             | Codename   | OS / firmware baseline                       | Validation status                  | Module status                 | Adaptation type                  |
| ----------------- | ---------- | -------------------------------------------- | ---------------------------------- | ----------------------------- | -------------------------------- |
| Xiaomi 17 Ultra   | `nezha`    | Android 17 / API 37<br>`OS4.0.0.15.XPACNXM`  | **Hardware verified**              | Installable                   | Native HIFI fix                  |
| Xiaomi 17 Ultra   | `nezha`    | Android 16 / API 36<br>`OS3.0.309.0.WPACNXM` | **Theoretical (offline OTA)**      | Installable with warning      | Native HIFI port                 |
| Xiaomi 17         | `pudding`  | Android 16 / API 36<br>`OS3.0.315.0.WPCCNXM` | **Theoretical (offline OTA)**      | Installable with warning      | AIDL HAL port                    |
| Xiaomi 17 Max     | `byron`    | Android 16 / API 36<br>`OS3.0.308.0.WAFCNXM` | **Theoretical (offline OTA)**      | Installable with warning      | AIDL HAL port                    |
| Xiaomi 17 Pro     | `pandora`  | Android 16 / API 36<br>`OS3.0.318.0.WBLCNXM` | **Theoretical (offline OTA)**      | Installable with warning      | AIDL HAL port                    |
| Xiaomi 17 Pro Max | `popsicle` | Android 16 / API 36<br>`OS3.0.318.0.WPBCNXM` | **Theoretical (offline OTA)**      | Installable with warning      | AIDL HAL port                    |
| Redmi K90 Pro Max | `myron`    | Android 16 / API 36<br>`OS3.0.308.0.WPMCNXM` | **Theoretical (offline OTA)**      | Installable with warning      | AIDL v3 / shifted-layout port    |
| Xiaomi 15         | `dada`     | Android 16 / API 36<br>`OS3.0.305.0.WOCCNXM` | **Theoretical (offline OTA)**      | Installable with warning      | AIDL v2 / PAL worker migration   |

“Hardware verified” means that the module has been tested on the actual device,
USB DAC and real playback applications.

“Theoretical” means that the complete OTA package was extracted from the target
firmware and passed semantic injection, branch relocation and two-pass
idempotence validation, but no corresponding physical device test was performed.

Theoretical compatibility does not mean confirmed audio stability or strict
Bit Perfect output.

When installing a theoretical target, the installer displays a prominent warning.
Installation continues only after confirmation by pressing either volume key.

Player allowlist:

- Apple Music (`com.apple.android.music`)
- NetEase Cloud Music (`com.netease.cloudmusic`)
- QQ Music (`com.tencent.qqmusic`)
- Spotify (`com.spotify.music`)

The output target is USB Audio.

Root environments:
- Magisk
- KernelSU with a valid metamodule

Speaker output, Bluetooth output, analogue headphone output and mixed routes are
not modified by this module.

Other Qualcomm Android 17 AIDL audio baselines display an unverified warning.
Continuation is allowed only when ELF architecture, unique code signatures,
object layouts and executable patch space all match.

Fingerprints, Build IDs and whole-file hashes are used only for diagnostics.
They do not replace structural validation and do not independently block
compatible OTA targets.

### Features

- Uses Xiaomi native `HifiSampleRateManager` to handle playback state and
  sample-rate switching.
- Adds 44.1 kHz capability to the Qualcomm USB audio path.
- Synchronizes AudioFlinger, AIDL HAL, PAL and USB output sample rates.
- Sets the initial HIFI output state to PCM32/48 kHz.
- When the final HIFI track stops, an idle DAC keeps the last sample rate until
  standby.
- When normal USB output is active, restores 48 kHz according to the actual
  takeover state.
- No resident daemon, polling loop, Zygisk component or application hook.

### Limitations

Output target: the current implementation is based on Xiaomi's remaining native
HIFI output path, not the Bit Perfect path introduced after Android 14.

Module overwrite upgrades are not supported.

Before installing another build, the existing module must be removed and the
device must be rebooted.

If the installer detects an active module with the same ID or a leftover module
directory, installation is aborted immediately.

The module modifies system SO files during installation and does not store a
complete set of stock SO libraries.

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
patch states abort. All seven Android 16 baselines passed offline injection and
two-pass idempotence checks against extracted OTA libraries and are enabled
after acknowledging that hardware validation is missing. None of this
certifies runtime stability or strict bit-perfect output.

### Porting requests

The collector has two non-interchangeable modes.

For a new-device port, do not install an existing ZIP. Completely uninstall
any previous copy of this module, reboot into the unmodified system view, then
run `bash scripts/collect_device_port.sh port --capture-transitions` with adb
and root available. Use `port` without the transition option only when the
interactive playback sequence is not currently possible. Port mode refuses an
installed or pending copy of this module.

For a problem after installation, preserve the failure state and run
`bash scripts/collect_device_port.sh issue --capture-transitions`, or `issue`
without that option when playback cannot be tested. Issue mode includes the
installed module metadata and overlay payload, live target libraries, current
audio state, and crash evidence. It is not a stock baseline and cannot be used
for a new-device port.

Both modes are read-only on the device and do not clear logs or copy partition
images, APKs, music, or app-private data. By default the script retains only
one `xiaomi-usb-dac-{port,issue}-*.tar.gz`, not a duplicate unpacked directory.
Use `--serial SERIAL` for multiple devices, `--keep-directory` when an unpacked
copy is explicitly needed, or `--no-archive` for a directory only. Review
`PRIVACY-REVIEW.txt` and `state/collection-warnings.txt` before attaching the
archive to an Issue.

The following requirements apply to a new-device port archive. It must include
the stock versions of the libraries at their original
paths. The current patch targets are `libaudiopolicymanagerdefault.so`,
`libaudioflinger.so`, the active USB/PAL implementation, and the Qualcomm Audio HAL. The policy
components and Xiaomi policy implementation libraries are required for layout
analysis even though this module does not overwrite them. For a HIDL device,
also include every existing `audio.primary*.so`, `audio.usb*.so`,
`audio.bluetooth*.so`, `android.hardware.audio@*.so`, matching HAL service
binaries, and the audio-related libraries shown in the service process maps.

Include active audio policy/module XML, policy-engine XML, VINTF manifests,
audio init RC files, AudioPolicy and AudioFlinger dumps, ALSA and USB state,
and logs covering 44.1, 48, 88.2, 96, 176.4, 192 and 384 kHz, return to
44.1 kHz, stop, and DAC reconnect. State
the DAC model, displayed rate, PCM format, effects/Dolby status, and observed
result. Do not upload APKs, music, or unrelated full logcat. Every new baseline
still requires complete semantic and layout validation before it is verified.
