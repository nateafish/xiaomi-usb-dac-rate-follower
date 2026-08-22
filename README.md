# Xiaomi USB DAC Rate Follower

Firmware-pinned Magisk/KernelSU research module for Xiaomi 17 Ultra (`nezha`),
Android 17 / API 37, OS `4.0.0.15.XPACNXM`.

Version `0.6.3-alpha` repairs Xiaomi's existing native Hifi sample-rate path
instead of building a second controller around it. It contains no daemon,
Zygisk hook, app modification, XML override, preferred-mixer writer, polling
loop, or live audioserver restart.

## Root cause

Xiaomi already ships a `HifiSampleRateManager` in
`/system/lib64/libaudiopolicymanagerdefault.so`. For allowed applications it
counts active AudioTracks by source sample rate and sends
`sampling_rate=<rate>` to the active output HAL.

The device also ships an AudioFlinger Hifi synchronization path in
`/system/lib64/libaudioflinger.so`: after the HAL accepts a rate change,
`MixerThread` can call `readOutputParameters_l(true)`, read the real HAL rate,
update its own sample rate, and recalculate track/buffer parameters in place.

The stock implementation has four behaviors that explain the hardware traces:

- Feature 6 constructs `HifiSampleRateManager`, but the shipped configuration
  leaves Feature 8 disabled, so `deep_buffer_out` is never created. Playback
  callbacks consequently stop at `isProfileSupported()`.
- the profile strategy is `FIRST_LOCK`, so gapless overlap can leave the first
  song's 44.1 kHz rate pinned while a 48/96 kHz song starts;
- the AudioFlinger synchronization branch runs only when the mixer's current
  rate is **above** 48 kHz. It therefore handles high-rate fallback but skips
  the exact 48 kHz ↔ 44.1 kHz boundary.
- the USB route is correctly declared as original sound (`usb_device:none`),
  but the Hifi manager initializes its separate `activeEffect` field to
  `UNKNOWN(3)`. Feature 8 is disabled by this firmware's Hifi configuration,
  so the field is not updated through `activeEffect` parameters. Stock accepts
  only `NONE(2)` and can therefore reject an effect-free USB request.

That second condition matches the observed baseline: rates above 48 kHz can
work, while 44.1/48 kHz switching is probabilistic, stale, or speed-altering.

## The guarded patch set

`0.6.3-alpha` changes only these firmware addresses:

| Library / offset | Stock | Patched | Purpose |
|---|---:|---:|---|
| `libaudiopolicymanagerdefault.so` `0xc3260` | Feature 8 early exit | `nop` | Create Xiaomi's existing `deep_buffer_out` profile without globally enabling Feature 8 |
| `libaudiopolicymanagerdefault.so` `0xd3bcc..0xd3c8f` | Xiaomi profile/app lookup | 196-byte selective check | Allow only Apple Music and NetEase |
| same library `0xd42c4` | `ldr w3, [x24,#8]` | `mov w3, wzr` | Select `LATEST_MAX` instead of `FIRST_LOCK` |
| same library `0xd55b4` | `b.eq 0xd55e0` | `b.hs 0xd55e0` | Accept `NONE(2)` and stale `UNKNOWN(3)` while still rejecting Dolby/MiSound |
| `libaudioflinger.so` `0x1b0a84` | `b.hi 0x1b0c2c` | `b 0x1b0c2c` | Synchronize MixerThread for 44.1/48 kHz too |
| `libdev_usb.so` `0x7160`, `0x717c` | 352.8 then 44.1 kHz | 44.1 then 352.8 kHz | Put 44.1 inside PAL's seven returned rates |

The whitelist is exactly:

- `com.apple.android.music`
- `com.netease.cloudmusic`

The `LATEST_MAX` strategy makes overlapping tracks deterministic: a new higher
rate takes effect immediately; a new lower rate takes effect after the old
higher-rate track stops. There is no timer or usage polling.

## PCM format and “bit perfect”

The tested QTI AIDL HAL path uses PCM32 as the USB mixer/output container. A
player may submit PCM16, PCM24, PCM32, or Float; normal AudioFlinger conversion
produces PCM32 for the HAL. This module fixes sample-rate following. It does not
claim strict bit identity when app DSP, effects, software volume, Float
conversion, or another processing stage changes samples.

## Firmware and mount safety

The ZIP does not redistribute Xiaomi system/vendor libraries. During installation it:

1. requires the exact fingerprint documented above;
2. validates ELF64/AArch64 headers, minimum sizes, semantic markers, stable
   instruction context, and a consistent known/patch state at every offset;
3. copies them into the module's systemless overlay;
4. applies 196 + 4 + 4 + 4 + 4 + 4 + 4 bytes of guarded patches;
5. rereads every patched offset, verifies unchanged file sizes and required
   package strings, then reports whole-file hashes as reference identifiers.

KernelSU requires an active metamodule such as official `meta-overlayfs`. There
is intentionally no manual bind-mount fallback. Magisk uses its standard
systemless mount mechanism.

## Build

```sh
ANDROID_NDK_HOME=/path/to/android-ndk bash scripts/build.sh
```

Every push to `main` builds and verifies the module. A `v*` tag publishes a
prerelease. See [TESTING.md](TESTING.md) for the rollout procedure and
[docs/research.md](docs/research.md) for the reverse-engineered call chain.

## Requesting support for another device

Do not install this ZIP on another model or firmware. Open a GitHub issue and
attach a ZIP or tar archive containing the following files from the target
device. Do not attach paid application APKs or music files.

- A text inventory with `ro.build.fingerprint`, `ro.vendor.build.fingerprint`,
  SDK version, product device, board platform, `ro.vendor.audio.hifi.config`,
  root solution/version, and active KernelSU metamodule if applicable.
- `/system/lib64/libaudiopolicymanagerdefault.so`
- `/system/lib64/libaudioflinger.so`
- `/vendor/lib64/libdev_usb.so`
- `/vendor/bin/hw/audiohalservice.qti` and
  `/vendor/lib64/hw/libaudiocorehal.qti.so` when present.
- Relevant files under `/vendor/etc/audio`, `/odm/etc/audio`, the active
  `audio_policy_configuration.xml`, audio VINTF manifests, and audio init RCs.
- `dumpsys media.audio_policy`, `dumpsys media.audio_flinger`, `/proc/asound/cards`,
  `/proc/asound/pcm`, and `/proc/asound/card*/stream0` while the DAC is attached.
- A logcat captured from starting one verified 44.1 kHz track, switching to a
  48 kHz track, and stopping playback. Include the player package name, DAC
  model, displayed rates, expected result, and actual result in the issue.

Remove unrelated personal log lines before uploading. Each supported firmware
needs its own reviewed target manifest: library paths, ELF/semantic markers,
instruction-context signatures, patch offsets, and accepted pre-patch states.
Whole-file hashes are reference identifiers, not the sole compatibility gate.

This is an experimental, exact-firmware alpha—not a universal Android
bit-perfect module.
