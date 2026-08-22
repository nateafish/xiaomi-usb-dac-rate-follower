# Test baseline and phased rollout

Baseline captured on 2026-08-22. Earlier live policy experiments caused audio
loss and device freezes, so this version is tested only across clean reboots.

## Required rate-transition matrix

Do not judge a build only by the first song after connecting the DAC. Capture
each transition below without stopping the app unless the row explicitly says
so:

| Case | Active streams | Expected USB rate |
|---|---|---|
| Cold start | Apple/NetEase 44.1 | 44.1 kHz |
| Gapless up | old 44.1 + new 48 | 48 kHz |
| Gapless down overlap | old 48 + new 44.1 | 48 kHz until old track stops, then 44.1 kHz |
| Hi-res up | old 44.1 + new 96 | 96 kHz |
| Duplicate prepared tracks | two 44.1 tracks, one stops | remains 44.1 kHz |
| Other app takes audio | selected app 44.1 + normal app 48 | 48 kHz or a clean policy-defined rejection; never slowed audio |
| Other app releases audio | normal app stops, selected app remains 44.1 | returns to 44.1 kHz |
| Full stop | no media clients | clean stream close; next song can configure again |

For every row, verify all three layers: AudioPolicy/Hifi manager event and
count, QTI HAL standby/configure, and AudioFlinger MixerThread readback. A DAC
display alone cannot distinguish a correct policy decision from a stale mixer
or backend.

The current v0.6.5 alpha adds lock-local arbitration for simultaneous HIFI and
Deep Buffer streams. A successful cold start still does not prove this path:
the other-app takeover/release rows must show exactly one effective transition
at each ownership boundary and no repeated HAL reopen loop.

## Exact baseline

| Item | Value |
|---|---|
| Device | Xiaomi 17 Ultra / `nezha` |
| Build | `OS4.0.0.15.XPACNXM` |
| Fingerprint | `Xiaomi/nezha/nezha:17/CP2A.260605.016/OS4.0.0.15.XPACNXM:user/release-keys` |
| Android | 17 / API 37 |
| Root | KernelSU `ksud 4.1.3` |
| Metamodule | Official `meta-overlayfs 1.3.1` |
| Audio HAL | Qualcomm AIDL |
| USB output | PCM32 mixer/HAL container |

Stock hashes:

```text
libaudiopolicymanagerdefault.so
e0bd4444461df3608f2baa05d4f5db22d0d5ddfb23cabb36474ff5f5c22da3cb

libaudioflinger.so
d499d92e115dac7ee8e7e5dcbd53079e6a61ffccbe6d34481f239813e1f3695f

libdev_usb.so
d36085dbf0e4f7979ee6b94540b216d949d0f74ab0cda385fdfd5cfc8cd0c296

libaudiocorehal.qti.so
388afd93534a81747a874f70fac2577e737db998c42dec6c02d109073335d298

/odm/etc/audio/audio_module_config_primary.xml
369b5a595837d78ee6d7f1ad7042129421d9cdc3ea27b1c229e8476a54c9f151
```

Patched hashes:

```text
libaudiopolicymanagerdefault.so
9dcedf72cb0a682f507495f1f048fc89eec614d842412964d98ebcfd635e645b

libaudioflinger.so
66ce065150b8d1e7cb056a7fbc6040563c9e8ef87c3068dd40dc5e876d9e95e6

libdev_usb.so
04cb4f2a7f4f4247995eb098b7d9a6ba8aeb6ff131144e87a6730d8a9ee4dad6

libaudiocorehal.qti.so
3d21f137b48d18eaec31b7958820940110b74d65b900a57d3e80b9b464b4fa78
```

## Safety rules

- Never hot-swap these libraries or restart audioserver during playback.
- Never run a root-side preferred-mixer writer during playback.
- Apply and roll back only by enabling/disabling the module and rebooting.
- Keep wireless ADB pairing and KernelSU safe-mode recovery available.
- Do not proceed to transitions until fresh-start 44.1 and 48 kHz each pass.

Before installation, the private exact-firmware verifier must pass against the
captured stock policy ELF. It checks both the archived v0.6.4 intermediate hash
and the v0.6.5 arbiter patch, including byte-idempotent reapplication:

```text
firmware patch verification: stock -> v0.6.4 -> v0.6.5 passed
```

## Phased test

1. With the old module disabled, record all three reference hashes and verify a working USB DAC.
2. Install `v0.6.5-alpha`; the installer must report matching ELF/semantic,
   XML structural state, instruction-context checks, and metamodule
   availability. Reboot normally.
3. Before opening a player, record all resulting hashes, confirm 44.1 kHz
   appears in the USB dynamic profile, confirm the Xiaomi manager created its
   `hifi_playback` profile without `sample rate cannot be 0`, and confirm
   audioserver is stable.
4. Open NetEase from a fresh process and play a known 44.1 kHz WAV. Verify the
   selected IOProfile is unflagged `hifi_playback` with mixer behavior DEFAULT;
   then verify the DAC, AudioFlinger MixerThread, HAL, and ALSA rates all become
   44.1 kHz.
5. Force-stop NetEase. Reopen it and play a 48 kHz WAV. Require all four layers
   to report 48 kHz with normal speed.
6. Repeat fresh-process tests at 96 kHz.
7. Test NetEase transitions: 44.1 → 48 → 44.1 → 96 → 48 kHz. Capture policy,
   AudioFlinger, HAL/PAL, ALSA, and DAC-display evidence for each boundary.
8. Repeat Apple Music fresh-start and transition tests using the sample rate it
   actually submits to AudioTrack—not catalog metadata.
9. Play from a non-whitelisted application. Xiaomi's Hifi manager must not
   follow it.
10. Test old/new song overlap, pause/resume, force-stop, USB unplug/replug, and
    a second app playing concurrently.

The v0.6.5 policy hash is
`9dcedf72cb0a682f507495f1f048fc89eec614d842412964d98ebcfd635e645b`.
Its profile-initialization patch changes the Feature 8 early exit at `0xc3260`
to a NOP. The effect-state patch changes the branch at `0xd55b4`. A live
v0.6.2 capture showed NetEase requesting 44100 Hz on USB, but there was no
`deep_buffer_out` profile configuration, `onPlaybackStarted`, or hardware
callback. Reverse engineering also found the USB-device callback that already
tries to create `hifi_playback`; its static default rate is zero, so stock
rejects it. v0.6.5 repairs that configuration and uses AOSP Preferred Mixer
DEFAULT behavior only to route whitelist media onto HIFI. Xiaomi's own
start/stop/rate-count callbacks remain the controller. The separate
NONE/UNKNOWN patch handles the Deep fallback without globally enabling Feature
8.

The new AIDL HAL patch is not a timer or repeated reconfiguration request. It
extends the HAL's existing sampling-rate usecase mask from VOIP/HIFI to
DEEP_BUFFER/VOIP/HIFI. The active ODM XML is changed in parallel because the
legacy HIDL policy advertised 44.1 kHz on Deep Buffer while the migrated AIDL
module dropped it. Either half alone is incomplete.

## Pass criteria

- No app crash, audioserver crash, device freeze, silent USB endpoint, or
  repeated rate-request loop.
- `dumpsys media.audio_policy` shows Deep Buffer PCM24 and PCM32 profiles at
  both 44100 and 48000 after reboot.
- Whitelisted media selects `hifi_playback` with flags NONE and behavior
  DEFAULT; no `BIT_PERFECT_PLAYBACK` usecase or reopen loop appears.
- MixerThread and HAL agree after every accepted `sampling_rate` change.
- 48 ↔ 44.1 kHz never changes playback speed.
- When no whitelisted track remains active, the output returns to Xiaomi's
  normal 48 kHz baseline.

## Recovery

Disable `xiaomi-usb-dac-rate-follower` in KernelSU/Magisk and reboot. If Android
does not reach the UI, create:

```text
/data/adb/modules/xiaomi-usb-dac-rate-follower/disable
```

from recovery or root ADB, then reboot. Removing/disabling the module restores
the physical stock libraries because the patches are systemless.
