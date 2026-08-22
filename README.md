# Xiaomi USB DAC Rate Follower

Firmware-pinned Magisk/KernelSU research module for Xiaomi 17 Ultra (`nezha`),
Android 17 / API 37, OS `4.0.0.15.XPACNXM`.

Version `0.6.6-alpha` repairs Xiaomi's existing native Hifi sample-rate path
instead of building a second controller around it. It contains no daemon,
Zygisk hook, app modification, polling loop, or live audioserver restart. A
small in-policy hook uses Android's existing Preferred Mixer API with DEFAULT
behavior to select Xiaomi's native `hifi_playback` path. It adds one systemless
ODM XML overlay.

## Root cause

Xiaomi already ships a `HifiSampleRateManager` in
`/system/lib64/libaudiopolicymanagerdefault.so`. For allowed applications it
counts active AudioTracks by source sample rate and sends
`sampling_rate=<rate>` to the active output HAL.

The device also ships an AudioFlinger Hifi synchronization path in
`/system/lib64/libaudioflinger.so`: after the HAL accepts a rate change,
`MixerThread` can call `readOutputParameters_l(true)`, read the real HAL rate,
update its own sample rate, and recalculate track/buffer parameters in place.

The stock implementation has several disconnected pieces that explain the
hardware traces:

- Xiaomi ships static configurations for `deep_buffer_out`, `hifi_playback`,
  and `voip_playback`. The HIFI configuration already uses `LATEST_MAX` and is
  restricted to USB, but its default sample rate is zero. USB attachment does
  call `createHifiProfile("hifi_playback")`; that function rejects the profile
  with `sample rate cannot be 0`.
- Ordinary Apple Music and NetEase tracks are still selected onto Deep Buffer.
  Nothing installs a package-specific Preferred Mixer entry that would select
  the unflagged, dynamic, USB-only `hifi_playback` profile.

- Feature 6 constructs `HifiSampleRateManager`, but the shipped configuration
  leaves Feature 8 disabled, so `deep_buffer_out` is never created. Playback
  callbacks consequently stop at `isProfileSupported()`.
- the Deep Buffer profile strategy is `FIRST_LOCK`, so gapless overlap can leave the first
  song's 44.1 kHz rate pinned while a 48/96 kHz song starts;
- the AudioFlinger synchronization branch runs only when the mixer's current
  rate is **above** 48 kHz. It therefore handles high-rate fallback but skips
  the exact 48 kHz ↔ 44.1 kHz boundary.
- the USB route is correctly declared as original sound (`usb_device:none`),
  but the Hifi manager initializes its separate `activeEffect` field to
  `UNKNOWN(3)`. Feature 8 is disabled by this firmware's Hifi configuration,
  so the field is not updated through `activeEffect` parameters. Stock accepts
  only `NONE(2)` and can therefore reject an effect-free USB request.
- the legacy HIDL policy declared `deep_buffer` at `44100 48000`, but the
  active AIDL ODM module declares both PCM24 and PCM32 deep-buffer profiles at
  48000 only. The AIDL HAL also triggers `standby()` for VOIP(8) and HIFI(13)
  rate changes, but omits DEEP_BUFFER_PLAYBACK(3).
- `sendkeySamplingRateToAHal(output, rate)` forwards `sampling_rate` without
  checking which devices are currently routed on that output. The earlier
  playback-event filter excludes speaker in one path but not Bluetooth, so the
  legacy manager can re-clock a Bluetooth output and change playback speed.

These conditions match the observed baseline: rates above 48 kHz can
work, while 44.1/48 kHz switching is probabilistic, stale, or speed-altering.

## The guarded patch set

`0.6.6-alpha` changes only these firmware addresses and one XML node:

| Library / offset | Stock | Patched | Purpose |
|---|---:|---:|---|
| `libaudiopolicymanagerdefault.so` `0x38800`, cave `0xc37ac..0xc3921` | HIFI default 0; Deep strategy 1 | HIFI default 48000; Deep strategy 0 | Complete Xiaomi's existing per-profile configuration without changing VoIP |
| same library `0x5575c` | direct Preferred Mixer lookup | guarded branch to cave | For whitelist media on a selected USB device type, install/reuse a DEFAULT PCM32 HIFI preference |
| `libaudiopolicymanagerdefault.so` `0xc3260` | Feature 8 early exit | `nop` | Create Xiaomi's existing `deep_buffer_out` profile without globally enabling Feature 8 |
| `libaudiopolicymanagerdefault.so` `0xd3bcc..0xd3c8f` | Xiaomi profile/app lookup | 196-byte selective check | Allow only Apple Music and NetEase |
| same library `0xd42c4` | per-profile strategy load | restored if an older module changed it | Keep VoIP stock; Deep/HIFI strategy comes from each static configuration |
| same library `0xd55b4` | `b.eq 0xd55e0` | `b.hs 0xd55e0` | Accept `NONE(2)` and stale `UNKNOWN(3)` while still rejecting Dolby/MiSound |
| same library `0xd57bc`, cave `0xc3928..0xc3adf` | per-profile `changed` test | shared HIFI/Deep arbitration | Use Xiaomi's existing active-rate counters to control the single physical USB backend |
| same library `0x7df94`, cave `0xc3ae0..0xc3b6b` | no routed-device check | branch to 140-byte USB-only gate | Resolve the exact output handle; permit the HAL parameter only when every routed device is USB |
| `libaudioflinger.so` `0x1b0a84` | `b.hi 0x1b0c2c` | `b 0x1b0c2c` | Synchronize MixerThread for 44.1/48 kHz too |
| `libdev_usb.so` `0x7160`, `0x717c` | 352.8 then 44.1 kHz | 44.1 then 352.8 kHz | Put 44.1 inside PAL's seven returned rates |
| `libaudiocorehal.qti.so` `0x230894..0x2308a3` | Reopen usecases 8/13 | Reopen usecases 3/8/13 | Let an accepted Deep Buffer rate change run the HAL's existing standby/reconfigure path |
| active ODM primary XML, `deep_buffer_out` | PCM24/PCM32 at 48000 | PCM24/PCM32 at 44100/48000 | Restore the capability present in the legacy HIDL policy |

The whitelist is exactly:

- `com.apple.android.music`
- `com.netease.cloudmusic`

The HIFI route uses Android's ordinary `AUDIO_MIXER_BEHAVIOR_DEFAULT`, not
`BIT_PERFECT`. The preference is created once per current whitelist owner and
USB port/strategy. Repeated AudioTracks from the same UID reuse the existing
`PreferredMixerAttributesInfo`, preserving AOSP's active-client count; a
different whitelist UID replaces ownership only when it actually requests an
output. Non-whitelisted UIDs ignore the preference and retain normal routing.

The transport check is deliberately placed at the final sender. It looks up
the callback's exact `audio_io_handle_t` in `AudioPolicyManager::mOutputs`,
then checks the current `DeviceVector`. Only `USB_ACCESSORY`, `USB_DEVICE`, and
`USB_HEADSET` are accepted. Unknown/empty routes, Bluetooth, speaker, wired,
and mixed USB/Bluetooth routes fail closed without sending `sampling_rate`.
Merely having a USB DAC attached is not sufficient.

The `LATEST_MAX` strategy makes overlapping tracks deterministic: a new higher
rate takes effect immediately; a new lower rate takes effect after the old
higher-rate track stops. There is no timer or usage polling.

### Alpha limitation: on-device arbitration and transport validation

The v0.6.6 patch set has passed offline binary/signature checks, six named USB
scenarios, four non-USB fail-closed scenarios, and 24,402 balanced event
traces, but has not yet passed the complete on-device transition matrix.
It replaces Xiaomi's final per-profile decision with a lock-local shared
backend arbiter: HIFI and Deep retain independent native counters; active Deep
temporarily wins; stopping the final Deep track restores the still-active HIFI
maximum; stopping the final selected HIFI track returns the backend to 48 kHz.
It creates no new persistent counter or worker.

Treat the ZIP as a saved research candidate, not a stable release, until cold
start, gapless 44.1/48/96 transitions, other-app takeover/release, full stop,
and repeated reconnect tests all pass. See [TESTING.md](TESTING.md).

## PCM format and “bit perfect”

The tested QTI AIDL HAL path uses PCM32 as the USB mixer/output container. A
player may submit PCM16, PCM24, PCM32, or Float; normal AudioFlinger conversion
produces PCM32 for the HAL. This module fixes sample-rate following. It does not
claim strict bit identity when app DSP, effects, software volume, Float
conversion, or another processing stage changes samples.

## Firmware and mount safety

The ZIP does not redistribute Xiaomi system/vendor libraries. During installation it:

1. requires the exact fingerprint documented above;
2. validates ELF64/AArch64 headers, minimum sizes, semantic markers, stable
   instruction context, and a consistent known/patch state at every offset;
   it also verifies the unmodified AudioPolicyComponents layouts used to map
   output handles to their current device types;
3. validates the active ODM XML as a stock or already-patched deep-buffer node;
4. copies the targets into the module's systemless overlay;
5. verifies the executable cave is completely empty (or exactly matches this
   build), applies narrow guarded binary regions, and changes only the two Deep
   Buffer sampling-rate attributes in the XML;
6. rereads every patched offset, verifies unchanged ELF file sizes and required
   package strings, then reports whole-file hashes as reference identifiers.

KernelSU requires an active metamodule such as official `meta-overlayfs`. There
is intentionally no manual bind-mount fallback. Magisk uses its standard
systemless mount mechanism.

## Build

```sh
ANDROID_NDK_HOME=/path/to/android-ndk bash scripts/build.sh
```

The public build runs the shared-rate model automatically. With a privately
captured stock policy library, the exact stock → v0.6.4 → v0.6.5 → v0.6.6 binary
transition can also be checked without installing anything:

```sh
python3 tests/verify_firmware_patch.py \
  /path/to/libaudiopolicymanagerdefault.so \
  dist/xiaomi-usb-dac-rate-follower-v0.6.6-alpha.zip
```

Every push to `main` builds and verifies the module. A `v*` tag publishes a
prerelease. See [TESTING.md](TESTING.md) for the rollout procedure and
[docs/research.md](docs/research.md) for the reverse-engineered call chain.

## Requesting support for another device

Do not install this ZIP on another model or firmware. Open a GitHub issue and
attach a ZIP or tar archive containing the following files from the target
device. Do not attach paid application APKs or music files.

- A text inventory with `ro.build.fingerprint`, `ro.vendor.build.fingerprint`,
  SDK version, product device, board platform, `ro.vendor.audio.hifi.config`,
  root solution/version, and active KernelSU metamodule if applicable.
- `/system/lib64/libaudiopolicymanagerdefault.so`
- `/system/lib64/libaudiopolicycomponents.so`
- `/system/lib64/libaudioflinger.so`
- `/vendor/lib64/libdev_usb.so`
- `/vendor/bin/hw/audiohalservice.qti` and
  `/vendor/lib64/hw/libaudiocorehal.qti.so` when present.
- Relevant files under `/vendor/etc/audio`, `/odm/etc/audio`, the active
  `audio_policy_configuration.xml`, audio VINTF manifests, and audio init RCs.
- `dumpsys media.audio_policy`, `dumpsys media.audio_flinger`, `/proc/asound/cards`,
  `/proc/asound/pcm`, and `/proc/asound/card*/stream0` while the DAC is attached.
- A logcat captured from starting one verified 44.1 kHz track, switching to a
  48 kHz track, and stopping playback. Include the player package name, DAC
  model, displayed rates, expected result, and actual result in the issue.

Remove unrelated personal log lines before uploading. Each supported firmware
needs its own reviewed target manifest: library paths, ELF/semantic markers,
instruction-context signatures, patch offsets, and accepted pre-patch states.
Whole-file hashes are reference identifiers, not the sole compatibility gate.

This is an experimental, exact-firmware alpha—not a universal Android
bit-perfect module.
