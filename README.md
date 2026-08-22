# Xiaomi 17 USB Whitelist Rate Follower

Device-specific Magisk/KernelSU research module for the Xiaomi 17 Android 17
Qualcomm AIDL audio stack.

Version `0.3.1-alpha` enables Xiaomi/AOSP's built-in deep-buffer sample-rate
manager, adds 44.1 kHz to the ordinary `deep_buffer_out` mixer, and activates
source-rate following only while a whitelisted app is playing through a USB
DAC. The default whitelist contains Apple Music and NetEase Cloud Music:

```text
com.apple.android.music
com.netease.cloudmusic
```

Edit `config/packages.list` before installation to add more packages.

## What is verified

- The USB DAC advertises 44.1 kHz and Qualcomm PAL accepts it.
- `ro.vendor.audio.hifi.config=15` enables Feature 8 and creates the missing
  `deep_buffer_out` HifiSampleRateManager profile.
- The manager receives the active package and source sample rate.
- With its effect gate set to `none`, AudioFlinger reopens a normal MIXER
  thread at 44.1 kHz and PAL selects 44.1 kHz.
- The manager's default rate is 48 kHz and it resets when the whitelist is idle.

## Important limitation

This build is not yet proven bit-perfect. It proves system-side sample-rate
following, but it does not yet prove that Dolby/MiSound/session effect chains,
software volume, and all processing are detached. The module name is retained
for upgrade compatibility; the release title deliberately says Rate Follower.

## Device lock

The bundled `libdev_usb.so` patch is firmware-specific. Installation aborts
unless `/vendor/lib64/libdev_usb.so` matches the known stock or patched SHA-256.
The vendor ABI exposes seven usable USB rate slots, so 44.1 kHz replaces
352.8 kHz; exposed rates are 44.1/48/88.2/96/176.4/192/384 kHz.

## KernelSU

KernelSU without a metamodule uses the included early bind-mount helper. It
applies the correct SELinux labels before mounting vendor/odm audio XML files.
No Zygisk or application injection is used.

## Build

```sh
bash scripts/build.sh
```

Every push to `main` builds and verifies the ZIP. Tags matching `v*` also
publish a GitHub Release. See `docs/research.md` for reverse-engineering notes.
