Xiaomi USB DAC Rate Follower v0.6.3-alpha

Exact-firmware research build for Xiaomi 17 Ultra OS4.0.0.15.XPACNXM on
Android 17. The installer verifies the build fingerprint, ELF architecture,
semantic markers, instruction context, and consistent patch state before
making a systemless copy. Whole-file hashes are reference identifiers only.

The module changes six narrow parts of Xiaomi's existing native Hifi path:

1. Xiaomi's existing deep_buffer_out Hifi profile is initialized without
   globally enabling Feature 8 or changing ro.vendor.audio.hifi.config.
2. HifiSampleRateManager allows only com.apple.android.music and
   com.netease.cloudmusic.
3. The profile strategy changes from FIRST_LOCK to LATEST_MAX so overlapping
   old/new song AudioTracks do not permanently pin the first song's rate.
4. AudioFlinger synchronizes MixerThread from the HAL after every accepted
   Hifi sampling_rate change, including 48 kHz -> 44.1 kHz and the reverse.
5. Qualcomm PAL's fixed seven-rate priority list includes 44.1 kHz instead of
   352.8 kHz, matching the DAC's verified native 44.1 kHz capability.
6. Xiaomi's deep-buffer guard accepts NONE(2) and stale UNKNOWN(3), while still
   rejecting real Dolby(0) and MiSound(1). USB is declared `usb_device:none`,
   but Feature 8 does not propagate it into the Hifi manager's separate field.

The USB/HAL mixer remains PCM32. PCM16, PCM24, or Float submitted by an app is
handled by normal AudioFlinger conversion. This build does not claim strict
bit identity when the app, effects, volume, or format conversion changes data.

There is no daemon, Zygisk injection, app patch, preferred-mixer writer, XML
edit, polling, or live audioserver restart. The ZIP ships only tiny patch blobs,
not Xiaomi's complete system or vendor libraries.

KernelSU requires an active metamodule such as official meta-overlayfs. The
module contains no manual bind-mount fallback. Magisk uses its standard
systemless mount.

EXPERIMENTAL: install only on the fingerprint accepted by customize.sh. Keep a
KernelSU/Magisk recovery path available. A reboot is required to apply or
remove the module.
