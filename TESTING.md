# Test baseline

Baseline captured on 2026-08-22. This file separates observed results from
features that still require end-to-end validation.

## Phone and software

| Item | Baseline |
|---|---|
| Product | Xiaomi 17 Ultra |
| Model | `2512BPNDAC` |
| Device codename | `nezha` |
| Board platform property | `canoe` |
| Android | 17 / API 37 |
| Build | `OS4.0.0.15.XPACNXM` |
| Build fingerprint | `Xiaomi/nezha/nezha:17/CP2A.260605.016/OS4.0.0.15.XPACNXM:user/release-keys` |
| Security patch | 2026-07-01 |
| Kernel | `6.12.69-android16-6-gb1493ec68d4a-abogki514973465-4k` |
| Root/module manager | KernelSU `ksud 4.1.3` |
| Audio HAL | Qualcomm AIDL; `IConfig/default`, `IModule/default`, and `IModule/usb` registered |
| Stock HiFi feature property | `ro.vendor.audio.hifi.config=13` |
| Module HiFi feature property | `15` (`13 | 0x2`, enabling Feature 8) |

This is a firmware-specific baseline. Other Xiaomi models, regional builds,
and firmware updates are unsupported unless their binaries and policy files
are independently checked.

## USB DAC baseline

The current live regression device is an iBasso DC-Tonfa, connected as ALSA
card 0 over high-speed USB. Its playback interface reports stereo PCM at
16-bit, packed 24-bit, and 32-bit, with these rates:

```text
44100 48000 88200 96000 176400 192000 352800 384000 705600 768000
```

Earlier capability work also used a Topping G5. The iBasso device is the
current baseline for subsequent whitelist and 44.1 kHz regression tests.

## Module artifacts

| Artifact | SHA-256 |
|---|---|
| `v0.3.1-alpha` ZIP | `bc9cfa5f92651b9f1f8c547fbdec797b477cba4356be8d527c0b33307751a330` |
| `set-audio-parameters` helper | `e830886ad9f321d9893d58297e8560be6b2ccd74f1b7dfff2919c0baaa24f491` |
| Patched `libdev_usb.so` | `04cb4f2a7f4f4247995eb098b7d9a6ba8aeb6ff131144e87a6730d8a9ee4dad6` |
| Expected stock `libdev_usb.so` | `d36085dbf0e4f7979ee6b94540b216d949d0f74ab0cda385fdfd5cfc8cd0c296` |

The installer rejects an unknown `libdev_usb.so` hash.

## Verified observations

- The DAC and USB ALSA layer advertise native 44.1 kHz.
- The Qualcomm USB capability patch makes 44.1 kHz visible inside the usable
  seven-rate vendor list; 352.8 kHz is displaced.
- `FeatureManager::isFeatureEnable(8)` is controlled by bit `0x2` of
  `ro.vendor.audio.hifi.config`.
- Setting the property to 15 before audioserver initialization creates the
  missing `deep_buffer_out` HifiSampleRateManager profile with 44.1/48 kHz,
  FIRST_LOCK strategy, and 48 kHz default.
- The built-in manager receives the active application package and source
  sample rate. It observed a 44.1 kHz application track correctly.
- With the manager's `activeEffect` gate set to `none`, AudioFlinger reopened
  the normal `deep_buffer_out` MIXER thread at 44100 Hz and Qualcomm PAL chose
  a 44100 Hz USB device configuration.
- The helper's `AudioSystem::setParameters` ABI call succeeds on this build.
- KernelSU installation of `v0.3.1-alpha` succeeds, validates the firmware
  hash, and stages both whitelist packages:
  `com.apple.android.music` and `com.netease.cloudmusic`.

## Not yet verified

- A full post-reboot regression of the staged `v0.3.1-alpha` module.
- Automatic whitelist transitions for both applications from start to stop,
  including a clean 48 -> 44.1 -> 48 kHz trace.
- Bit-identical output. Existing Dolby, MiSound, session effects, software
  volume, or other processing may still alter samples.
- Application stability after the new whitelist controller becomes active.
- Automatic normal-Mixer following above 48 kHz; this alpha specifically adds
  44.1/48 kHz to `deep_buffer_out`.

The project must therefore be described as a source-rate follower alpha, not
as a completed bit-perfect implementation.

## Recovery baseline

If the device becomes unstable, disable `xiaomi17-bitperfect` in KernelSU and
reboot. The pre-update module directory was backed up on the test device before
installing this alpha. Do not restart audioserver manually during normal use;
the module is designed to take effect during an ordinary boot.
