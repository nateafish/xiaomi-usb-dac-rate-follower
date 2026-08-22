# Test baseline and safe rollout

Baseline captured on 2026-08-22. Observed results and pending tests are kept
separate because earlier live policy experiments froze the device twice.

## Phone and software

| Item | Baseline |
|---|---|
| Product/model | Xiaomi 17 Ultra / `2512BPNDAC` |
| Device/platform | `nezha` / Qualcomm `canoe` audio configuration |
| Android | 17 / API 37 |
| Build | `OS4.0.0.15.XPACNXM` |
| Build fingerprint | `Xiaomi/nezha/nezha:17/CP2A.260605.016/OS4.0.0.15.XPACNXM:user/release-keys` |
| Security patch | 2026-07-01 |
| Root | KernelSU `ksud 4.1.3` |
| Zygisk | Zygisk Next `1.4.5 (836)` |
| Target ABIs | Apple Music and NetEase Cloud Music: `arm64-v8a` |
| Audio HAL | Qualcomm AIDL: `IConfig/default`, `IModule/default`, `IModule/usb` |

The live USB DAC exposes stereo PCM at 16-bit, packed 24-bit, and 32-bit with:

```text
44100 48000 88200 96000 176400 192000 352800 384000 705600 768000
```

The firmware-specific PAL patch exposes these seven entries to Android:

```text
44100 48000 88200 96000 176400 192000 384000
```

## Verified observations

- USB descriptors and ALSA advertise native 44.1 kHz.
- Qualcomm's dynamic capability ABI has seven usable rate entries plus a zero
  terminator. Without reordering, 44.1 kHz falls outside the seven returned
  entries for the tested DAC.
- Patched `libdev_usb.so` SHA-256:
  `04cb4f2a7f4f4247995eb098b7d9a6ba8aeb6ff131144e87a6730d8a9ee4dad6`.
- Expected stock SHA-256:
  `d36085dbf0e4f7979ee6b94540b216d949d0f74ab0cda385fdfd5cfc8cd0c296`.
- A preconfigured 44.1 kHz / PCM32 preferred mixer created an AudioFlinger
  `BIT_PERFECT` thread at 44.1 kHz on USB.
- Apple Music submitted both 44.1 and 48 kHz tracks to Android during live
  traces; catalog metadata was not used for the decision.

## Failed 0.4 design

The old ordinary-mixer experiment is archived and must not be installed. It
patched `libaudiopolicymanagerdefault.so`, changed Xiaomi's `deep_buffer_out`
strategy from `FIRST_LOCK` to `LATEST_MAX`, and bypassed an effect gate.

Reverse engineering found the important ordering error:

```text
AudioTrack/output already selected and started
        -> HifiSampleRateManager.onPlaybackStarted()
        -> sendkeySamplingRateToAHal("sampling_rate=...")
```

The first 44.1 kHz stream worked because the parameter arrived before PAL's
first stream start. On a later 48 kHz track, AudioPolicy and AudioFlinger could
report 48 kHz while the open PAL/USB stream remained 44.1 kHz. The observed
ratio `44100 / 48000 = 0.91875` explains the playback-speed error.

A live `setPreferredMixerAttributes(... BIT_PERFECT)` call while playback was
active was associated with a complete device freeze. No test in this project
may repeat live policy writes, audioserver restarts, or policy-library swaps
during active playback.

## Current boot warning

The old module has a `disable` marker but its files remain mounted until the
next reboot. Before any `0.5.1-alpha` test, verify that mountinfo contains no
`xiaomi17-bitperfect` paths and that the stock system policy library is active.
Do not install the new alpha into the current contaminated boot.

## Phased 0.5 test plan

1. Reboot once with the old module disabled. Verify the old policy and XML
   mounts are gone. Do not start a player yet.
2. Install `xiaomi-usb-dac-rate-follower` and reboot normally. Confirm only
   `libdev_usb.so` and the two XML files are overlaid; the system policy library
   must remain stock.
3. Open Apple Music without playing. Confirm the Zygisk log says the
   `native_setup` hook was installed. If the app crashes, disable the module and
   reboot; do not retry with audioserver modifications.
4. From a fresh Apple Music process, play one known 44.1 kHz PCM media track.
   Require all of the following before proceeding:
   - hook log: requested rate 44100 and `preferred=accepted`;
   - AudioFlinger thread type `BIT_PERFECT`;
   - thread/HAL/processing rates all 44100;
   - PAL USB backend and DAC display both 44.1 kHz.
5. Force-stop the app, reopen it, and test one 48 kHz track as a fresh-start
   case. Require the same evidence at 48 kHz.
6. Only after both fresh-start tests pass, test 44.1 -> 48 -> 44.1 transitions.
   Capture the old track STOP, new track creation, preferred-mixer result,
   AudioFlinger output reopen, PAL media configuration, and DAC display.
7. Repeat fresh-start and transition tests for NetEase Cloud Music.
8. Finally test a non-whitelisted app. It must remain on the stock 48 kHz mixer
   and must not produce any rate-follower hook log.

## Recovery

The new module ID is `xiaomi-usb-dac-rate-follower`. If the device becomes
unstable, create its `disable` marker from recovery/ADB or disable it in the
KernelSU manager, then reboot. The previous module ID is
`xiaomi17-bitperfect`; keep it disabled or remove it only when the phone is in a
known-good boot.

Do not manually restart audioserver as a recovery shortcut. A full reboot is
the defined rollback boundary for audio HAL and policy overlays.
