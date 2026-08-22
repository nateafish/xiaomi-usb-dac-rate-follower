# Xiaomi 17 Android 17 USB 采样率跟随研究

## 当前结论

这台设备的 44.1 kHz 限制横跨三层，单改 XML 或单改普通 Mixer 都不够：

```text
应用 AudioTrack（包名、真实源采样率）
        ↓
AOSP Audio Policy / preferred mixer（选择输出并决定是否重开）
        ↓
QTI AIDL Audio HAL（读取动态 USB profile）
        ↓
Qualcomm PAL / libdev_usb.so（USB 能力数组只有 7 个有效速率）
        ↓
USB DAC
```

`0.5.1-alpha` 的设计是：修正 HAL 暴露的 44.1 kHz 能力，启用系统已有的
动态 `hifi_playback` BitPerfectThread，然后仅在目标应用创建 PCM 媒体
`AudioTrack` 之前，按该音轨的真实格式设置 preferred mixer。它不再尝试
在普通 deep-buffer 流已经运行后改变 PAL 采样率。

## 本机 HAL 与配置承载位置

本机是 Qualcomm AIDL Audio HAL，关键服务和文件如下：

- `/vendor/bin/hw/audiohalservice.qti`
- `/vendor/lib64/hw/libaudiocorehal.qti.so`
- `/vendor/lib64/hw/libaudiocorehal.default.so`
- `/vendor/lib64/libaudioaidlcommon.so`
- `/vendor/lib64/libaudioplatformconverter.qti.so`
- `/vendor/lib64/libdev_usb.so`
- `/vendor/etc/init/audiohalservice_qti.rc`
- `/vendor/etc/vintf/manifest/manifest_audiocorehal_default.xml`
- `/odm/etc/audio/audio_module_config_primary.xml`
- `/vendor/etc/audio/audio_module_config_primary.xml`
- `/odm/etc/audio/resourcemanager_canoe_mtp.xml`
- `/system_ext/lib64/libaudiohalvendorextn.so`

因此“配置是否写在 HAL 里”的答案是：两边都有。

- XML 承载 mix port、profile、route 和 `BIT_PERFECT` flag。
- AIDL HAL 把 PAL 的 USB 动态能力转换为 framework audio profile。
- PAL 与 `libdev_usb.so` 解析 USB 描述符、选择设备配置，并决定实际返回
  哪些采样率。
- AOSP Audio Policy 负责 preferred mixer 的所有权、profile 匹配、输出
  reopen 和 AudioFlinger 线程类型。

## 44.1 kHz 为什么消失

PAL 的动态能力 ABI 定义了 7 个有效采样率和 1 个零终止项：

```cpp
#define MAX_SUPPORTED_SAMPLE_RATES 7
uint32_t sample_rate[MAX_SUPPORTED_SAMPLE_RATES + 1];
```

测试 DAC 支持的速率多于 7 个。厂商优先级表使 44.1 kHz 排在第 8 个可用
值，所以 USB 描述符匹配日志能看到 44.1，AIDL 动态 profile 最终却没有它。
不能把第 8 个终止槽直接填满，否则上层按零扫描会越界读取后续字段。

模块保持 ABI 不变，只交换本机 `libdev_usb.so` 中 44.1 和 352.8 kHz 的
优先级常量：

```text
stock SHA-256:
d36085dbf0e4f7979ee6b94540b216d949d0f74ab0cda385fdfd5cfc8cd0c296

patched SHA-256:
04cb4f2a7f4f4247995eb098b7d9a6ba8aeb6ff131144e87a6730d8a9ee4dad6

0x7160: 352800 -> 44100
0x717c: 44100  -> 352800
```

补丁后的 7 个动态速率为：

```text
44100 48000 88200 96000 176400 192000 384000
```

## 系统已有的 Bit Perfect 路径

设备 XML 已经有一个无静态 profile 的动态端口：

```xml
<mixPort name="hifi_playback" role="source">
</mixPort>
```

它只路由到 `usb_device_out` 和 `usb_headset`，但 stock XML 没有 flag。
模块把两份有效配置改为：

```xml
<mixPort name="hifi_playback" role="source" flags="BIT_PERFECT">
</mixPort>
```

Android 17 的 `AudioPolicyManager` 会为 USB 设备寻找带动态 profile 且匹配
采样率、格式、声道和 `BIT_PERFECT` flag 的输出。preferred mixer 改变时，
framework 可以关闭并按目标格式重开该输出；AudioFlinger 随后建立
`BitPerfectThread`。本机已验证预先设置 44.1 kHz / PCM32 后能进入 44.1
kHz BitPerfectThread。

## 为什么普通 Mixer 方案失败

反编译 `/system/lib64/libaudiopolicymanagerdefault.so` 后确认，小米
`HifiSampleRateManager` 的调用时序是：

- `AudioPolicyManager::startOutput()` 末尾调用 `onPlaybackStarted()`；
- `stopOutput()` 调用 `onPlaybackStopped()`；
- `triggerHardwareSampleRateUpdate()` 最终只回调
  `AudioPolicyManager::sendkeySamplingRateToAHal()`；
- 该函数向当前 output 发送 `sampling_rate=...` 参数。

也就是说，它在 output/track 已经选好之后才决策。第一次 44.1 kHz 能成功，
是因为参数赶在 PAL 第一次启动前到达；后续 48 kHz 只改变 framework 的名义
状态，已打开的 PAL 流仍保持 44.1 kHz。这不是 `FIRST_LOCK` 单一策略问题，
所以把策略改为 `LATEST_MAX` 也不能解决硬件流 reopen。

小米扩展库 `/system_ext/lib64/libaudiopolicymanagerimpl.so` 也已检查：

- `AudioPolicyManagerImpl::selectOutput()` 处理的是 CE bypass 和 duplicate
  output，不是 HiFi 包名路由；
- `setOutputClientInfo()` 根据 AttributionSource UID 解析包名并设置小米 app
  mask，但不把目标包迁移到 `hifi_playback`。

因此没有一个现成“小米白名单 XML”可直接开启逐曲 USB 原采样率输出。

## 0.5 的应用侧切入点

设备 `framework.jar` 中的 Android 17 注册签名已经逐项核对：

```text
android.media.AudioTrack.native_setup
(Object weakThis,
 Object audioAttributes,
 int[] sampleRate,
 Object channelMasks,
 int audioFormat,
 int bufferSize,
 int mode,
 int[] sessionId,
 Parcel attribution,
 long nativeTrack,
 boolean offloaded,
 int encapsulationMode,
 Object tunerConfiguration,
 String opPackageName,
 String codecProvenance) -> int
```

这是比 audioserver 后处理更合适的点，因为同一调用里同时存在：

- 当前应用进程/包名；
- `AudioAttributes` usage；
- 实际 `sampleRate[0]`；
- 源 PCM encoding 和 channel mask（preferred 输出统一选择 PCM32）；
- 原生 AudioTrack 尚未创建这一时序保证。

Zygisk API 的 `hookJniNativeMethods` 直接替换已注册 JNI 项，不需要修改
Apple Music APK，也不需要对启用 PAC/BTI 的系统库做 inline hook。模块仅匹配：

```text
com.apple.android.music[:process]
com.netease.cloudmusic[:process]
```

hook 只处理 `USAGE_MEDIA`、非 offload、PCM、USB 已连接的音轨。它构建与
源采样率/编码/声道一致的 `AudioMixerAttributes`，设置
`MIXER_BEHAVIOR_BIT_PERFECT`，随后无条件调用原始 `native_setup`。任何 Java
API 查找、权限或 profile 匹配异常都会被清除并回退到原始建轨，避免把异常
带回应用。

## KernelSU 注入条件

KernelSU 自身不提供 Zygisk。测试机已安装 Zygisk Next 1.4.5，目标应用均为
`arm64-v8a`，对应模块文件为 `zygisk/arm64-v8a.so`。XML/so overlay 与应用
进程注入是两件事：

- 有 metamodule 时，由 KernelSU/metamodule 处理 systemless 文件 overlay；
- 无 metamodule 时，模块在 post-fs-data 阶段只 bind mount
  `libdev_usb.so` 和两份 XML；
- Zygisk Next 负责将 arm64 模块载入目标应用。

## 安全边界与待验证项

- 不在活动播放期间调用 root-side preferred mixer 写入。
- 不重启 audioserver，不热替换 AudioPolicyManager，不修改普通 48 kHz mixer。
- 旧 `0.4` system policy 补丁不得进入新 ZIP。
- 应用内 EQ、音量归一化、空间音频或软件音量仍可能在 AudioTrack 之前改变
  样本；Android 的 BitPerfectThread 不能还原已经被应用处理的数据。
- 逐曲 gapless 切换可能让旧、新 AudioTrack 短暂重叠，必须按测试文档观察
  preferred mixer 更新、output reopen 和 PAL 配置顺序后才能宣称完成。

## 对应 AOSP / HAL 路径

Framework 重点检查：

- `frameworks/av/services/audiopolicy/managerdefault/AudioPolicyManager.cpp`
  - `setPreferredMixerAttributes()`
  - `getOutputForAttrInt()`
  - `reopenOutput()`
- `frameworks/av/services/audioflinger/Threads.cpp`
  - `BitPerfectThread`
- `frameworks/base/media/java/android/media/AudioManager.java`
  - `setPreferredMixerAttributes()`
- `frameworks/base/media/java/android/media/AudioMixerAttributes.java`
- `frameworks/base/core/jni/android_media_AudioTrack.cpp`
- `frameworks/av/media/libaudioclient/AudioTrack.cpp`
- `system/media/audio/include/system/audio.h`

公开实现参考：

- [Android preferred mixer attributes](https://source.android.com/docs/core/audio/preferred-mixer-attr)
- [AOSP AudioPolicyManager preferred mixer / reopen](https://android.googlesource.com/platform/frameworks/av/+/8f4ff60a672a5609d63cf3c6ec668da842c7900c/services/audiopolicy/managerdefault/AudioPolicyManager.cpp)
- [AudioReach PAL dynamic capability ABI](https://github.com/AudioReach/audioreach-pal/blob/88ad5461a87735124c2daa321a114c5806445e4b/inc/PalDefs.h#L620-L623)
- [AudioReach PAL USB sample-rate selection](https://github.com/AudioReach/audioreach-pal/blob/88ad5461a87735124c2daa321a114c5806445e4b/device/USBAudio/src/USBAudio.cpp#L815-L840)
- [QTI AIDL HAL USB capability conversion](https://github.com/sonyxperiadev/vendor-qcom-opensource-audio-hal-primary-hal-ar/blob/b071e74ead44a7aecee69969003b902632cd4ab3/hal/core/platform/Platform.cpp#L417-L480)
