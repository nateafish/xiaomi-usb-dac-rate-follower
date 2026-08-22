# Xiaomi USB DAC Rate Follower

Device-specific Magisk/KernelSU research module for the Xiaomi 17 Ultra
(`nezha`), Android 17 / API 37, and its Qualcomm AIDL audio stack.

Version `0.5.1-alpha` moves sample-rate selection to the only point that has
both the target package identity and the real source format: immediately before
the app creates an `AudioTrack`. A Zygisk hook is loaded only into Apple Music
and NetEase Cloud Music. For PCM media tracks with a connected USB DAC, it asks
Android 17 for a PCM32 preferred mixer matching the track's sample rate and
channel layout. Preference-only attributes omit the players' `DEEP_BUFFER`
flag, which otherwise makes AOSP search for a nonexistent
`DEEP_BUFFER | BIT_PERFECT` USB profile. The original `AudioTrack.native_setup`
then runs unchanged, and AudioFlinger performs its normal source-to-PCM32
conversion when the app submits Float, PCM16, or PCM24.

## Why the architecture changed

The failed `0.4.0-alpha` experiment changed Xiaomi's ordinary
`deep_buffer_out` mixer and patched the system AudioPolicyManager. Reverse
engineering and live traces showed that Xiaomi's rate manager runs after the
output is selected and only sends `sampling_rate=...` to the HAL. It can set
44.1 kHz before the first PAL stream opens, but it cannot safely reconfigure an
already running 44.1 kHz PAL stream to 48 kHz. The policy descriptor changed to
48 kHz while the USB backend stayed at 44.1 kHz, causing audible speed errors.
A live preferred-mixer write during active playback was also associated with a
device freeze. That design is removed from this version.

`0.5.1-alpha` contains no system AudioPolicyManager binary patch, polling
daemon, audio-parameter helper, audioserver restart, or ordinary-mixer rate
modification.

## Components

- A firmware-locked `libdev_usb.so` patch puts 44.1 kHz inside Qualcomm PAL's
  seven-entry dynamic USB rate list. It displaces 352.8 kHz.
- The stock dynamic `hifi_playback` mix port is marked `BIT_PERFECT` in both
  ODM and vendor audio module configurations.
- An arm64 Zygisk module hooks the exact Android 17
  `AudioTrack.native_setup` registration only in:
  - `com.apple.android.music`
  - `com.netease.cloudmusic`
- Non-media, compressed/offload, non-USB, and non-target application tracks
  fall through to stock behavior.

## What is verified

- The DAC and ALSA layer support native 44.1 kHz.
- Qualcomm PAL accepts 44.1 kHz after the seven-rate capability patch.
- With a preferred mixer configured before track creation, Android 17 can open
  a 44.1 kHz `BIT_PERFECT` thread on this HAL.
- Live traces confirmed that `DEEP_BUFFER` in the target apps' media attributes
  prevented later preferred-mixer requests from matching the hifi profile.
- Both target applications are arm64, and the device has Zygisk Next 1.4.5 on
  KernelSU 4.1.3.
- The Zygisk source compiles cleanly against NDK 29 and the module ZIP passes
  structural and negative-content checks.

## Not yet verified

- PCM32 rate-following transitions such as 44.1 -> 48 -> 96 kHz remain to be
  tested in phases on the hardware display.
- Bit identity still depends on the player not changing samples before
  `AudioTrack` (EQ, normalization, spatial processing, or software volume).
- Apple Music can only be followed at the rate it actually submits to Android,
  which may differ from catalog metadata.
- A Float or PCM16 source converted by AudioFlinger into PCM32 is not strict
  bit identity, even when sample rate follows correctly.

Do not describe this alpha as a completed universal bit-perfect solution.

## Device and root requirements

Installation aborts unless `/vendor/lib64/libdev_usb.so` matches the known
stock or patched SHA-256 for the tested firmware. Android 17 / API 37 is also
required. KernelSU users need Zygisk Next or another compatible Zygisk provider.
KernelSU without a metamodule uses the included early bind-mount helper for the
vendor library and the two XML files.

## Build

```sh
bash scripts/build.sh
```

Set `ANDROID_NDK_HOME` when the NDK is not discoverable from
`ANDROID_SDK_ROOT`. Every push to `main` builds and verifies the ZIP. Tags
matching `v*` also publish a GitHub Release.

See [TESTING.md](TESTING.md) for the phased test and recovery procedure, and
[`docs/research.md`](docs/research.md) for HAL/AOSP paths and reverse-engineering
evidence.
