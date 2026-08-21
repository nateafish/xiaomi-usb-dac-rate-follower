# Xiaomi 17 USB 44.1 kHz Bit Perfect

Device-specific proof-of-concept Magisk/KernelSU module for the Xiaomi 17 Android 17 Qualcomm AIDL audio stack.

The connected Topping G5 reports 44.1 kHz, but Qualcomm PAL exposes only seven sample-rate entries and the stock priority table places 44.1 kHz eighth. This module swaps the priority positions of 44.1 and 352.8 kHz, enables the dynamic `hifi_playback` Bit Perfect mix port, and pre-arms Android preferred mixer attributes for Apple Music and NetEase Cloud Music.

Tested result on Xiaomi 17 + Topping G5:

```text
Thread type: BIT_PERFECT
Sample rate: 44100 Hz
HAL format: PCM32
Output device: USB_HEADSET
```

## Exposed USB rates

```text
44.1 / 48 / 88.2 / 96 / 176.4 / 192 / 384 kHz
```

The vendor ABI has seven usable rate slots plus one zero terminator, so 352.8 kHz is intentionally sacrificed.

## Safety warning

This repository contains a firmware-specific patched `libdev_usb.so`. The installer verifies the source library SHA-256 and refuses installation on an unknown build. Do not bypass that check or install the ZIP on another device or firmware.

The module targets these packages and resolves their UIDs dynamically:

- `com.netease.cloudmusic`
- `com.apple.android.music`

If a player was already running when the module or DAC became active, stop it completely and reopen it once. Android does not migrate an existing mixed AudioTrack to a BitPerfectThread.

## GitHub build

Every push to `main`, every version tag, and every manual workflow dispatch performs a clean build:

1. Compiles `daemon/BitPerfectDaemon.java`.
2. Converts it to Android DEX using Android build-tools 37.
3. Verifies the patched Qualcomm library SHA-256.
4. Packages the Magisk module as `xiaomi17-bitperfect-v0.2.0-poc.zip`.
5. Publishes the ZIP and checksum as a GitHub Actions artifact.

Tags matching `v*` also publish the ZIP and checksum as permanent GitHub Release assets.

The generated module is a proof of concept and is not automatically installed.

## Research

See [docs/research.md](docs/research.md) for the device evidence, HAL/AOSP paths, exact truncation mechanism, patch offsets, and reversible test results.
