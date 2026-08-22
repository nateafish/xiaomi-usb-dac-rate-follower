# Xiaomi Android 17 USB rate-following research

## Conclusion

The tested firmware already contains almost the entire native rate-following
implementation. The missing behavior is not a single USB XML declaration:

```text
allowed app AudioTrack starts/stops
        ↓
Xiaomi HifiSampleRateManager counts active source rates
        ↓
ProfileManager chooses a hardware rate
        ↓
AudioPolicyManager sends sampling_rate=<rate> to the output HAL
        ↓
QTI AIDL HAL / PAL changes the USB backend
        ↓
AudioFlinger MixerThread must read back and adopt the HAL rate
```

The v0.6.2 design repairs this existing chain. It does not create a second state
machine or repeatedly inspect playback from userspace.

## Where configuration lives

This is a Qualcomm AIDL Audio HAL device. Relevant device paths include:

- `/vendor/bin/hw/audiohalservice.qti`
- `/vendor/lib64/hw/libaudiocorehal.qti.so`
- `/vendor/lib64/libaudioaidlcommon.so`
- `/vendor/lib64/libdev_usb.so`
- `/vendor/etc/init/audiohalservice_qti.rc`
- `/vendor/etc/vintf/manifest/manifest_audiocorehal_default.xml`
- `/vendor/etc/audio/audio_module_config_primary.xml`
- `/odm/etc/audio/audio_module_config_primary.xml`
- `/system/lib64/libaudiopolicymanagerdefault.so`
- `/system/lib64/libaudioflinger.so`
- `/system_ext/lib64/libaudiopolicymanagerimpl.so`

Configuration therefore exists in several forms:

- XML describes mix ports, profiles, routes, flags, and dynamic capabilities.
- The QTI AIDL HAL translates PAL USB capabilities into framework profiles.
- PAL/vendor code parses descriptors and selects the real endpoint format.
- Xiaomi's system AudioPolicyManager extension carries app whitelist, profile
  strategy, active-track counts, and the HAL `sampling_rate` callback.
- AudioFlinger carries the live MixerThread/HAL synchronization logic.

## Xiaomi HifiSampleRateManager

Reverse engineering of the exact system policy library found:

- built-in `deep_buffer_out` profile, default 48 kHz;
- built-in whitelist originally containing WeChat and QQ;
- `onPlaybackStarted()` and `onPlaybackStopped()` lifecycle integration;
- per-rate active application counts;
- `FIRST_LOCK` and `LATEST_MAX` strategies;
- `triggerHardwareSampleRateUpdate()`;
- `sendkeySamplingRateToAHal()`, which sends `sampling_rate=<rate>` to the
  selected output.

The firmware property `ro.vendor.audio.hifi.config=13` enables Xiaomi features
6, 7, and 9. Feature 7 is the important AudioFlinger Hifi synchronization path.

### Why FIRST_LOCK fails gapless playback

Apple Music and similar players prepare the next AudioTrack before the old song
is fully stopped. With `FIRST_LOCK`, the first active 44.1 kHz track owns the
hardware rate and a newly started 48/96 kHz track cannot replace it. This
matches the observed stale 44.1 kHz output and speed errors.

`LATEST_MAX` uses the active rate counts already maintained by Xiaomi. During
overlap, the highest active rate wins; after the old high-rate track stops, the
lower new rate becomes eligible. This is deterministic and event-driven.

## AudioFlinger’s hidden 48 kHz boundary

`MixerThread::checkForNewParameter_l()` in the exact `libaudioflinger.so`
contains the decisive condition:

```asm
1b0a78  ldr w8, [x28,#0x304]   // MixerThread current sample rate
1b0a7c  mov w9, #48000
1b0a80  cmp w8, w9
1b0a84  b.hi 0x1b0c2c
```

At `0x1b0c2c`, feature 7 eventually calls:

```text
PlaybackThread::readOutputParameters_l(true)
```

That method queries the HAL's actual output parameters, updates MixerThread's
sample rate, and recalculates minimum frame count, buffers, and tracks. Xiaomi's
own strings include `HIFI: readOutputParameters_l mSampleRate:%d`.

Stock therefore synchronizes only when the *current* mixer rate is above 48
kHz. Both 48 → 44.1 and 44.1 → 48 skip the call. Replacing `b.hi` with the same
function's unconditional branch enables Xiaomi's original in-place update for
the missing low-rate boundary. It avoids closing the output, returning
`DEAD_OBJECT`, restoring AudioTracks, or duplicating Hifi reference counts.

## Xiaomi's false global-effect gate

`HifiSampleRateManager::handlePlaybackEvent()` special-cases
`deep_buffer_out`. If the manager's global `activeEffect` is not `none`, stock
logs `deep_buffer with active effect, skipping sample rate management` and
returns before its app allow check.

The v0.6.1 live capture proved this state is too broad for USB: NetEase's
`TrackClientDescriptor` carried 44100 Hz, the dynamic USB profile contained
44100 Hz, and AudioFlinger's USB `AudioOut_15` thread had zero effect chains.
Nevertheless, a separate global `DAP_offload` Dolby state caused Xiaomi to
skip the event, so no `sampling_rate=44100` reached QTI AIDL HAL/PAL.

At exact file offset `0xd55b4`, v0.6.2 changes the conditional branch to the
same function's normal continuation at `0xd55e0`. That continuation still
executes `isAppAllowed()`, whose replacement accepts only Apple Music and
NetEase. The patch therefore removes no per-package restriction and adds no
polling; it only prevents an unrelated global effect state from vetoing an
effect-free USB output thread.

## Why the Qualcomm USB capability patch remains necessary

The DAC descriptor and ALSA endpoint advertise native 44.1 kHz, but QTI PAL's
dynamic capability ABI returns only seven rates plus a zero terminator. On this
firmware, 44.1 kHz is the eighth matching priority and disappears from the AIDL
USB profile. A clean v0.6 boot without the vendor micro-patch confirmed that
AudioPolicy exposed only `48000, 88200, 96000, 176400, 192000, 352800, 384000`.

The guarded `libdev_usb.so` patch swaps two uint32 priorities:

```text
0x7160: 352800 -> 44100
0x717c:  44100 -> 352800
```

This preserves the seven-entry ABI and makes the framework/Hifi manager see
44.1 kHz. It does not fill the zero terminator or scan beyond the array.

## Selective package handling

The exported `HifiSampleRateManager::isAppAllowed(profile, app)` thunk has one
direct internal implementation. v0.6.2 replaces that implementation with a
196-byte PAC-compatible function that:

- preserves the stock prologue and epilogue addresses for unwind compatibility;
- decodes Android libc++ short and long `std::string` representations;
- accepts exact package names only;
- embeds no writable state and performs no allocation or external call.

The function was compiled with NDK 29 and run as an arm64 test executable on
the target phone. Apple Music and NetEase returned true; WeChat, QQ, truncated,
extended, and empty names returned false.

## Why this is not a strict Float/bit-perfect claim

The QTI USB path on this device uses PCM32 as the mixer/HAL format. Float is not
a supported final USB HAL format. A Float or narrower integer source can be
converted by normal AudioFlinger processing into PCM32 while preserving the
requested sample rate. Rate following and strict bit identity are separate:
effects, normalization, software volume, app DSP, or Float conversion can still
change sample values.

## AOSP paths to inspect

- `frameworks/av/services/audiopolicy/managerdefault/AudioPolicyManager.cpp`
  - `startOutput()` / `stopOutput()`
  - `setParameters()` and output reopen behavior
- `frameworks/av/services/audioflinger/Threads.cpp`
  - `MixerThread::checkForNewParameter_l()`
  - `PlaybackThread::readOutputParameters_l()`
- `frameworks/av/media/libaudioclient/AudioTrack.cpp`
- `system/media/audio/include/system/audio.h`
- `hardware/interfaces/audio/aidl/default/`

The strongest evidence for this build is the exact on-device binary and live
HAL trace; AOSP explains the surrounding standard behavior, while the Xiaomi
feature gates and 48 kHz condition are vendor modifications.

## KernelSU mounting

KernelSU 3+ delegates system overlays to one active metamodule. The test phone
now uses official `meta-overlayfs 1.3.1`; `/data/adb/metamodule` points to it and
its ext4 content image mounts successfully. v0.6.2 intentionally refuses a
KernelSU installation without an active metamodule and contains no custom bind
fallback.
