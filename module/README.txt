Xiaomi 17 USB 44.1 kHz Bit Perfect - proof of concept

This module is device- and build-specific. It overlays the captured Qualcomm
AIDL primary audio configuration, adds BIT_PERFECT to hifi_playback, and
replaces this build's libdev_usb.so with a minimal binary patch.

The DAC's raw USB mask already contains 44.1 kHz. Qualcomm's fixed PAL device
capability structure returns only seven rates, and the stock priority table
places 44.1 kHz eighth. The patch swaps the priority positions of 44.1 and
352.8 kHz. Exposed USB rates become:
  44.1, 48, 88.2, 96, 176.4, 192 and 384 kHz

Tradeoff: 352.8 kHz is no longer exposed. No resampler is added by this patch.

The daemon resolves UIDs dynamically and only targets:
  com.netease.cloudmusic
  com.apple.android.music

It waits for an ALSA USB audio card and pre-arms a 44.1 kHz PCM32 Bit Perfect
mixer as soon as a target app becomes foreground. This must happen before the
app creates AudioTrack; Android does not migrate an existing mixed track to a
BitPerfectThread. Once playback exists, the daemon follows supported source
rates observed in AudioFlinger. Android stores one preferred media owner per
USB output, so the daemon switches that owner when playback moves between the
two target apps. It does not modify either application.

If the app was already playing when the module/USB DAC became active, stop it
completely and open it again once. On the tested Xiaomi 17 + Topping G5,
NetEase Cloud Music then opened a real 44.1 kHz BIT_PERFECT output thread.

Limitations:
  - The application must expose the source rate to AudioTrack; an app that
    resamples internally cannot be repaired by this module.
  - For bit-perfect output, keep player and system digital processing/volume
    changes disabled. The Android Bit Perfect path itself rejects mixing/SRC.
  - The initial pre-arm assumes 44.1 kHz because it is the common case for
    Apple Music and NetEase. An app that internally outputs 48 kHz cannot be
    made 44.1-bit-perfect by the daemon.
  - 352.8 kHz is sacrificed because the vendor ABI has seven usable rate slots
    plus one zero terminator; increasing the count would overrun into format.
  - This is a device-specific proof of concept. Test it with a recovery path
    available. Do not install it on a different firmware build.

Log: /data/adb/xiaomi17-bitperfect/daemon.log
