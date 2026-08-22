Xiaomi USB DAC Rate Follower v0.6.6-alpha

Exact-firmware research build for Xiaomi 17 Ultra OS4.0.0.15.XPACNXM on
Android 17. The installer verifies the build fingerprint, ELF architecture,
semantic markers, instruction context, dependent AudioPolicyComponents object
layouts, and consistent patch state before making a systemless copy. Whole-file
hashes are reference identifiers only.

The module reconnects Xiaomi's existing native Hifi path with narrow,
firmware-pinned changes:

1. The built-in hifi_playback configuration gets a nonzero 48000 Hz bootstrap
   rate, allowing Xiaomi's existing USB-attach callback to create it.
2. Apple Music and NetEase media on the two USB output ports use Android's
   existing Preferred Mixer mechanism with DEFAULT behavior to select the
   unflagged dynamic hifi_playback profile. Repeated tracks from the same UID
   reuse the owner record instead of resetting active-client counts.
3. Xiaomi's existing deep_buffer_out Hifi profile is initialized without
   globally enabling Feature 8 or changing ro.vendor.audio.hifi.config.
4. HifiSampleRateManager allows only com.apple.android.music and
   com.netease.cloudmusic.
5. Deep Buffer changes from FIRST_LOCK to LATEST_MAX in its own static profile;
   HIFI retains LATEST_MAX and VoIP retains its stock strategy.
6. AudioFlinger synchronizes MixerThread from the HAL after every accepted
   Hifi sampling_rate change, including 48 kHz -> 44.1 kHz and the reverse.
7. Qualcomm PAL's fixed seven-rate priority list includes 44.1 kHz instead of
   352.8 kHz, matching the DAC's verified native 44.1 kHz capability.
8. Xiaomi's deep-buffer guard accepts NONE(2) and stale UNKNOWN(3), while still
   rejecting real Dolby(0) and MiSound(1). USB is declared `usb_device:none`,
   but Feature 8 does not propagate it into the Hifi manager's separate field.
9. The active AIDL ODM XML restores the HIDL-era 44100/48000 PCM24 and PCM32
   declarations on deep_buffer_out.
10. Qualcomm's AIDL HAL sampling-rate gate includes DEEP_BUFFER_PLAYBACK(3) in
   the same existing standby/reconfigure path as VOIP(8) and HIFI(13).
11. A 440-byte lock-local arbiter reads Xiaomi's existing HIFI and Deep active
   rate counters. Deep temporarily owns the shared USB backend; when it becomes
   idle, a still-active HIFI stream regains its rate. No new state is counted.
12. A final sender-side gate resolves the exact output handle and permits the
   sampling_rate parameter only when every currently routed device is USB.
   Bluetooth, speaker, wired, mixed USB/Bluetooth, empty, and unknown routes
   fail closed and remain under Android's stock policy.

The USB/HAL mixer remains PCM32. PCM16, PCM24, or Float submitted by an app is
handled by normal AudioFlinger conversion. This build does not claim strict
bit identity when the app, effects, volume, or format conversion changes data.

There is no daemon, Zygisk injection, app patch, userspace preferred-mixer
writer, polling, or live audioserver restart. The installer makes a structural edit to
the device's own XML copy; the ZIP ships only tiny patch blobs, not Xiaomi's
complete system or vendor libraries.

This release deliberately does not add BIT_PERFECT to hifi_playback. On this
firmware that flag selects a separate Qualcomm BIT_PERFECT_PLAYBACK usecase
which previously entered a stream-not-configured reopen loop. Rate following
is tested separately from strict sample-bit identity.

KNOWN ALPHA LIMITATION: shared-backend arbitration has passed the offline event
model and exact-binary patch checks, but not the complete on-device transition
matrix. This build is for controlled testing and is not yet a stable daily-use
release.

KernelSU requires an active metamodule such as official meta-overlayfs. The
module contains no manual bind-mount fallback. Magisk uses its standard
systemless mount.

EXPERIMENTAL: install only on the fingerprint accepted by customize.sh. Keep a
KernelSU/Magisk recovery path available. A reboot is required to apply or
remove the module.
