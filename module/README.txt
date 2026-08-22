Xiaomi USB DAC Rate Follower v0.7.3-alpha

Exact-firmware research build for Xiaomi 17 Ultra OS4.0.0.15.XPACNXM on
Android 17. The installer validates the fingerprint, ELF architecture, call
sites, executable caves, and every object-layout offset used by the hook. A
mixed, older, or partially patched source state is rejected before writing.

This build uses a native firmware-pinned path:

1. AOSP runs Xiaomi's original selectOutput callback normally.
2. For com.apple.android.music or com.netease.cloudmusic only, the final output
   handle changes to an already-open hifi_playback descriptor when both the
   originally selected output and HIFI output are currently USB-only.
3. Xiaomi's existing HifiSampleRateManager receives normal HIFI start/stop
   events and remains the only sample-rate controller.
4. Qualcomm's seven returned USB rates include 44.1 kHz while retaining
   352.8 kHz in the displaced priority slot.
5. AudioFlinger reads the accepted HAL rate at the 44.1/48 kHz boundary too.
6. The final sampling_rate sender permits writes only when every device routed
   on that exact output is USB. Bluetooth, speaker, wired, mixed, empty, stale,
   and duplicating routes fail closed.
7. When Xiaomi's native LATEST_MAX HIFI count reaches zero, the same stop
   lifecycle restores the shared USB backend to the normal 48 kHz mixer rate.
8. The dynamic hifi_playback profile starts at PCM32/48 kHz. MixerThread, the
   AIDL FMQ and PAL therefore agree at creation, and QTI's stock 40 ms frame
   calculation naturally produces 1920 frames.
9. Qualcomm's HIFI usecase is admitted to the existing PAL reconfiguration
   path so later native rate events update PAL and AudioFlinger together.

No output is opened or reopened by the selection hook. It allocates no object,
creates no preference, adds no counter, and runs no daemon, polling loop,
Zygisk code, or live audioserver restart.

The USB path remains a PCM32 MixerThread and this module targets sample-rate
following, not strict sample-bit identity. App DSP, effects, software volume,
format conversion, and concurrent playback may still prevent bit-perfect data.

Disabling NetEase crossfade does not disable AudioFlinger's protective fade
when NetEase recreates its AudioTrack. The coherent 48 kHz startup state avoids
carrying a 384 kHz-sized queue into low-rate playback; it does not remove the
safety fade itself.

The idle restoration occurs when Android delivers the final native HIFI stop
event. It does not forcibly migrate a client that remains active. NetEase also
uses a separate Deep Buffer transition track and Android fade handling while it
recreates its main HIFI AudioTrack; this build does not override those gains.

KernelSU requires an active metamodule such as meta-overlayfs. Install only on
the exact fingerprint accepted by customize.sh and keep a recovery path.
