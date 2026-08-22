# Test baseline and phased rollout

Baseline captured on 2026-08-22. Earlier live policy experiments caused audio
loss and device freezes, so this version is tested only across clean reboots.

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
```

Patched hashes:

```text
libaudiopolicymanagerdefault.so
44d6d59dd395c2a5dfee6d3cf2c2f1a485377633a9e6d3b78754cc2b1b3f92c3

libaudioflinger.so
66ce065150b8d1e7cb056a7fbc6040563c9e8ef87c3068dd40dc5e876d9e95e6
```

## Safety rules

- Never hot-swap these libraries or restart audioserver during playback.
- Never run a root-side preferred-mixer writer during playback.
- Apply and roll back only by enabling/disabling the module and rebooting.
- Keep wireless ADB pairing and KernelSU safe-mode recovery available.
- Do not proceed to transitions until fresh-start 44.1 and 48 kHz each pass.

## Phased test

1. With the old module disabled, verify both stock hashes and a working USB DAC.
2. Install `v0.6.0-alpha`; the installer must report exact fingerprint/hash
   acceptance and metamodule availability. Reboot normally.
3. Before opening a player, verify both patched hashes are visible through
   `/system/lib64` and audioserver is stable.
4. Open NetEase from a fresh process and play a known 44.1 kHz WAV. Verify the
   DAC, AudioFlinger MixerThread, HAL, and ALSA rates all become 44.1 kHz.
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

## Pass criteria

- No app crash, audioserver crash, device freeze, silent USB endpoint, or
  repeated rate-request loop.
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
