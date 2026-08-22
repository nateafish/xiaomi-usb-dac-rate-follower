# Controlled test plan

`0.7.2-alpha` must pass offline verification before any device installation.
Do not live-replace audio libraries or restart audioserver manually.

## Offline gate

The build must confirm:

- all AArch64 branch encodings and the 744-byte native cave;
- no unresolved relocations;
- the 140-byte final USB sender gate;
- exact stock call-site and object-layout signatures;
- same-size patched ELF images and byte-idempotent reapplication;
- all routing and final transport-gate fail-closed cases, including bounded
  output and device collections.

The private firmware check is:

```sh
python3 tests/verify_firmware_patch.py \
  libaudiopolicymanagerdefault.so \
  libaudioflinger.so \
  libdev_usb.so \
  libaudiocorehal.qti.so \
  libaudiopolicycomponents.so \
  libaudiopolicymanagerimpl.so \
  dist/xiaomi-usb-dac-rate-follower-v0.7.2-alpha.zip
```

## Installation gate

Install only if:

- fingerprint exactly matches the installer;
- KernelSU has an active metamodule, or Magisk systemless mounting is known to
  work;
- the previous module is disabled/removed and the phone has rebooted back to
  stock libraries;
- a recovery path is available;
- the battery is sufficiently charged.

The installer must report a completely `stock` structural state. Any mixed or
older state is a hard failure, not a warning.

## First boot health

Before playing audio, verify:

- `audioserver` and `audiohalservice.qti` each have one stable PID;
- no repeated process deaths, tombstones, stream-not-configured loops, or
  rapid `openOutput`/`reopenOutput` messages occur;
- system UI and the player remain responsive;
- speaker playback works with the DAC disconnected.
- an idle/48 kHz HIFI thread reports about 1920 HAL frames, not 15360.

If any process restarts or the UI stalls, stop testing and disable the module
from recovery/root. Do not repeatedly reopen a player against a dying audio
service.

## Primary same-app matrix

Use verified local files or tracks whose source rates are known. For both
NetEase and Apple Music, test each transition at least five times:

| Sequence | Expected USB/MixerThread rate |
|---|---|
| cold start 44.1 | 44.1 |
| 44.1 -> 48 | 48 |
| 48 -> 44.1 | 44.1 |
| 44.1 -> 96 | 96 |
| 96 -> 44.1 | 44.1 |
| 48 -> 96 -> 48 | 48 -> 96 -> 48 |
| full stop, then 44.1 | 44.1 on the new start |

For every boundary, capture all four observations:

1. app/source rate and package;
2. policy output handle and IOProfile name;
3. AudioFlinger MixerThread rate/format;
4. HAL `sampling_rate` line and DAC display.

Passing only the DAC display is insufficient.

## Stress and lifecycle matrix

After the primary matrix passes:

- 30 alternating 44.1/48 transitions;
- 20 alternating 44.1/96 transitions;
- pause/resume and seek near a track boundary;
- gapless/prebuffered transitions;
- stop the app, unplug/replug the DAC, and repeat;
- kill/relaunch the app with the DAC attached;
- disconnect the DAC while playback is active.

There must be no repeated rate-request storm, dead output, distorted speed,
audioserver restart, or growing UI latency.

## Fail-closed transport matrix

With the module active, verify that target packages retain stock behavior on:

- speaker;
- Bluetooth A2DP/LE;
- wired analogue output if available;
- a route change from USB to Bluetooth during playback;
- USB attached but Bluetooth selected.

No module-induced `sampling_rate` parameter should be sent to a non-USB or
mixed output. Bluetooth playback speed must remain correct.

## Cross-application matrix (research only)

This alpha does not claim cross-app ownership. Record, but do not treat as a
release pass, these sequences:

- target 44.1 starts, then another app 48 starts/stops;
- another app 48 is already active, then target 44.1 starts;
- target app switches while a notification/system sound occurs.

The logs are needed to identify a native migration/lifecycle point. Do not add
a daemon or restore the rejected HIFI/Deep shared counter merely to force the
expected display.

## Success criteria

The alpha may advance only when:

- every same-app transition changes policy/HAL/MixerThread/DAC coherently;
- full stop and reconnect remain repeatable;
- no output or process death occurs under stress;
- all non-USB cases remain untouched;
- the exact logs are archived with firmware, module commit and DAC model.
