# Xiaomi 17 Android 17 USB 44.1 kHz / Bit Perfect 研究结果

## 结论

这台 Xiaomi 17（Android 17 / SDK 37 / Qualcomm canoe）已经实机跑通 USB 44.1 kHz Bit Perfect。问题不是 USB DAC 或 ALSA 不支持 44.1，也不是 XML 没声明 44.1，而是 Qualcomm PAL 的动态能力结构最多只返回 7 个采样率；Topping G5 支持的 44.1 kHz 在厂商优先级表中排第 8，因此被截掉。

最终方法由三部分组成：

1. 在本机 `libdev_usb.so` 的采样率优先级表中交换 44.1 kHz 与 352.8 kHz 的位置，让 44.1 进入前 7 项。
2. 给 AIDL HAL 的动态 `hifi_playback` mixPort 增加 `flags="BIT_PERFECT"`。
3. 在 Apple Music 或网易云音乐创建 AudioTrack 之前，为当前前台播放器调用 Android preferred mixer API，预设 44.1 kHz、PCM32、`MIXER_BEHAVIOR_BIT_PERFECT`。

补丁后暴露的 USB 采样率为：

```text
44100, 48000, 88200, 96000, 176400, 192000, 384000
```

代价是 352.8 kHz 不再暴露。没有加入重采样器，也没有把 44.1 升频到 88.2；44.1 内容可以直接进入 44.1 BitPerfectThread。

## AIDL HAL 与配置承载位置

这台设备同时存在“XML 配置”和“HAL/PAL 二进制逻辑”，两者都影响最终能力：

```text
/odm/etc/audio/audio_module_config_primary.xml
        ↓ 端口、路由、flags
vendor.audio-hal-aidl / audiohalservice.qti
        ↓ getUsbProfiles()
PAL_PARAM_ID_DEVICE_CAPABILITY
        ↓
/vendor/lib64/libdev_usb.so
        ↓ 解析 USB 描述符、生成动态采样率数组
Audio Policy / preferred mixer attributes
        ↓
AudioFlinger BitPerfectThread
```

本机关键路径：

- 服务：`/vendor/bin/hw/audiohalservice.qti`
- AIDL：`android.hardware.audio.core.IConfig/default`、`IModule/default`、`IModule/usb`
- 主配置：`/odm/etc/audio/audio_module_config_primary.xml`
- vendor fallback：`/vendor/etc/audio/audio_module_config_primary.xml`
- PAL ResourceManager：`/odm/etc/audio/resourcemanager_canoe_mtp.xml`
- USB 能力实现：`/vendor/lib64/libdev_usb.so`
- AIDL core HAL：`/vendor/lib64/hw/libaudiocorehal.qti.so`
- PAL client：`/vendor/lib64/libar-pal.so`、`/vendor/lib64/libpalclient.so`

ResourceManager 配置中 USB 设备已经设置 `<fractional_sr>1</fractional_sr>`，说明 44.1/88.2 系列并未被全局禁用；`hifi_filter=false` 也不是这次 USB 44.1 缺失的原因。

## 44.1 kHz 被截掉的准确原因

公开 AudioReach PAL 源码和本机二进制完全吻合。结构定义为 7 个有效采样率加 1 个零终止项：

```cpp
#define MAX_SUPPORTED_SAMPLE_RATES 7
uint32_t sample_rate[MAX_SUPPORTED_SAMPLE_RATES + 1];
```

USB 能力生成逻辑只循环 `min(7, popcount(mask))` 次，每次取最低置位 bit。厂商表的原始顺序为：

```text
384000, 352800, 192000, 176400, 96000, 88200, 64000,
48000, 44100, 32000, 24000, 22050, 16000, 11025, 8000
```

Topping G5 的 PAL 原始 mask 为 `0x1bf`，包含：

```text
384000, 352800, 192000, 176400, 96000, 88200, 48000, 44100
```

实机 PAL 日志先明确记录 `sr 44100 ... matches!!`，随后动态返回值却只有前 7 项：

```text
P 384000
P 352800
P 192000
P 176400
P 96000
P 88200
P 48000
```

因此 44.1 并非“不支持”，而是第 8 项被固定上限截断。QTI AIDL HAL 的 `getSampleRatesFromProfile()` 只是把这个零终止数组复制到 AIDL profile，并没有再次过滤 44.1。

不能简单把上限从 7 改成 8：数组第 8 个槽位承担零终止作用，而 AIDL HAL 会一直扫描到零；填满 8 个值会越过数组读到紧随其后的 `format[0]`。安全做法是保持 ABI 不变，只调整 44.1 的优先级。

## 二进制补丁

模块只修改本机固件的 `/vendor/lib64/libdev_usb.so` 两个 32 位常量位置：

```text
原始 SHA-256:
d36085dbf0e4f7979ee6b94540b216d949d0f74ab0cda385fdfd5cfc8cd0c296

补丁 SHA-256:
04cb4f2a7f4f4247995eb098b7d9a6ba8aeb6ff131144e87a6730d8a9ee4dad6

0x7160: 352800 → 44100
0x717c: 44100  → 352800
```

实机临时 bind mount 后，音频 HAL 和 audioserver 均正常重启，动态 USB profile 立即变为：

```text
44100, 48000, 88200, 96000, 176400, 192000, 384000
```

## Bit Perfect 实机验证

`hifi_playback` 使用 Qualcomm XML 解析器接受的短 flag：

```xml
<mixPort name="hifi_playback" role="source" flags="BIT_PERFECT">
</mixPort>
```

加载配置后，Audio Policy 显示 `hifi_playback` 带 `0x100000 (BIT_PERFECT)`，动态 USB preferred mixer 同时提供 default 和 bit-perfect 两类属性。

在 USB 端口 38 上，为网易云 UID 10347 设置：

```text
sample rate: 44100
format: PCM32
mixer behavior: BIT_PERFECT
setPreferredMixerAttributes status: 0
```

关闭并重新打开网易云，使 AudioTrack 在 preferred mixer 已经设置后创建，AudioFlinger 实际进入：

```text
Thread type: BIT_PERFECT
Sample rate: 44100 Hz
HAL format: PCM32
Processing format: PCM32
Output device: USB_HEADSET
Output flags: 0x100000 BIT_PERFECT
```

这证明 44.1 kHz 已经进入 Android 原生 BitPerfectThread，而不是普通 48 kHz Mixer，也不是 44.1 → 88.2 升频路径。本机 `/proc/asound/card0/stream0` 的运行状态一直显示 Stop，不能作为可靠判断；AudioFlinger、Audio Policy 和 HAL 活动流三者一致才是本次验证依据。

## Magisk 模块设计

0.2.0 POC 包含：

1. ODM 和 vendor 两份 `audio_module_config_primary.xml` 覆盖，给动态 `hifi_playback` 增加 `BIT_PERFECT`。
2. 本机固件专用的 `system/vendor/lib64/libdev_usb.so` 定点补丁。
3. root-side DEX 守护进程和 `service.sh`。

守护进程动态解析以下包名的 UID，不再硬编码安装编号：

- `com.netease.cloudmusic`
- `com.apple.android.music`

当 USB DAC 存在且目标应用进入前台时，它会在 AudioTrack 创建前预设 44.1/PCM32 Bit Perfect；播放建立后，再根据 AudioFlinger 暴露的受支持源采样率更新下一次请求。Android 对同一 USB 媒体策略只保存一个 preferred owner，因此守护进程只把所有权给当前前台或活动的目标播放器。

如果安装模块、插入 DAC 时应用已经在播放，需要彻底关闭并重新打开播放器一次。Android 不会把已经存在的 mixed AudioTrack 自动迁移到 BitPerfectThread。

## 限制与安全边界

- 模块只适用于这台设备当前固件；原始 `libdev_usb.so` SHA-256 不一致时不得安装。
- 352.8 kHz 被牺牲，原因是 vendor ABI 只有 7 个有效采样率槽。
- 初始预设按 44.1 kHz 处理，适合 Apple Music/网易云的常见内容；若应用内部已经输出 48 kHz，模块不能从 48 kHz 还原原始 44.1 数据。
- 严格 bit-perfect 仍要求关闭播放器 EQ、音量归一化、空间音频等应用内处理，并避免数字音量改变。
- 模块未自动安装；研究期间的所有 HAL/XML 测试都采用可撤销临时挂载。

## 44.1 → 88.2 备用路线

独立的 88.2 kHz Mixer POC 也已实机验证：网易云保持 PCM16/44100 AudioTrack，AudioFlinger 普通 Mixer 以 PCM32/88200 向 USB 输出。它能避开 48 kHz 锁定，但属于重采样，不是 Bit Perfect。既然严格 44.1 路径现已打通，优先使用 0.2.0 Bit Perfect 模块，只有兼容性需要时再使用 88.2 Mixer 测试包。

## 对应公开源码

- [AudioReach PAL：动态能力结构定义](https://github.com/AudioReach/audioreach-pal/blob/88ad5461a87735124c2daa321a114c5806445e4b/inc/PalDefs.h#L620-L623)
- [AudioReach PAL：USB 采样率 mask 截取与优先级表](https://github.com/AudioReach/audioreach-pal/blob/88ad5461a87735124c2daa321a114c5806445e4b/device/USBAudio/src/USBAudio.cpp#L815-L840)
- [QTI AIDL HAL：从 PAL 获取 USB 动态能力](https://github.com/sonyxperiadev/vendor-qcom-opensource-audio-hal-primary-hal-ar/blob/b071e74ead44a7aecee69969003b902632cd4ab3/hal/core/platform/Platform.cpp#L417-L480)
- [QTI AIDL HAL：复制零终止采样率数组](https://github.com/sonyxperiadev/vendor-qcom-opensource-audio-hal-primary-hal-ar/blob/b071e74ead44a7aecee69969003b902632cd4ab3/hal/core/platform/PlatformUtils.cpp#L117-L123)
- [Android：Preferred mixer attributes on USB devices](https://source.android.com/docs/core/audio/preferred-mixer-attr)
