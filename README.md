# Xiaomi USB DAC Rate Follower

Firmware-pinned Magisk/KernelSU research module for Xiaomi 17 Ultra (`nezha`),
Android 17 / API 37, OS `4.0.0.15.XPACNXM`.

Version `0.6.2-alpha` repairs Xiaomi's existing native Hifi sample-rate path
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

The stock implementation has three behaviors that explain the hardware traces:

- the profile strategy is `FIRST_LOCK`, so gapless overlap can leave the first
  song's 44.1 kHz rate pinned while a 48/96 kHz song starts;
- the AudioFlinger synchronization branch runs only when the mixer's current
  rate is **above** 48 kHz. It therefore handles high-rate fallback but skips
  the exact 48 kHz ↔ 44.1 kHz boundary.
- `deep_buffer_out` is rejected whenever Xiaomi's global effect state says
  Dolby or MiSound is active. On the tested USB route, Dolby was globally
  active while the USB MixerThread itself had zero effect chains, so a valid
  NetEase 44.1 kHz request was discarded before any HAL update.

That second condition matches the observed baseline: rates above 48 kHz can
work, while 44.1/48 kHz switching is probabilistic, stale, or speed-altering.

## The guarded patch set

`0.6.2-alpha` changes only these firmware addresses:

| Library / offset | Stock | Patched | Purpose |
|---|---:|---:|---|
| `libaudiopolicymanagerdefault.so` `0xd3bcc..0xd3c8f` | Xiaomi profile/app lookup | 196-byte selective check | Allow only Apple Music and NetEase |
| same library `0xd42c4` | `ldr w3, [x24,#8]` | `mov w3, wzr` | Select `LATEST_MAX` instead of `FIRST_LOCK` |
| same library `0xd55b4` | `b.eq 0xd55e0` | `b 0xd55e0` | Continue past the false global-effect gate to the existing app allow check |
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
2. verifies SHA-256 of all three stock libraries;
3. copies them into the module's systemless overlay;
4. applies 196 + 4 + 4 + 4 + 4 + 4 bytes of guarded patches;
5. verifies the complete patched-library SHA-256 before installation succeeds.

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

This is an experimental, exact-firmware alpha—not a universal Android
bit-perfect module.
