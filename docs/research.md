# Android 17 / Xiaomi AIDL USB audio research notes

These notes describe the exact Xiaomi 17 Ultra firmware pinned by this
repository. Addresses and object layouts are not portable to another build.

## Where configuration lives

This is a Qualcomm AIDL Audio HAL device. Relevant layers are split across:

- AOSP policy and Xiaomi's native Hifi manager in
  `/system/lib64/libaudiopolicymanagerdefault.so`;
- policy object implementations in
  `/system/lib64/libaudiopolicycomponents.so`;
- Xiaomi's policy extension in
  `/system_ext/lib64/libaudiopolicymanagerimpl.so` and its stub library;
- AudioFlinger in `/system/lib64/libaudioflinger.so`;
- Qualcomm USB capability parsing in `/vendor/lib64/libdev_usb.so`;
- QTI stream/usecase handling in
  `/vendor/lib64/hw/libaudiocorehal.qti.so`;
- active module and policy XML under `/odm/etc/audio` and `/vendor/etc/audio`.

XML declares ports, routes and static profiles, but it is not the complete
source of truth. Dynamic USB profiles come through the AIDL HAL and
`libdev_usb`; package policy and live sample-rate control are native code.

## Stock output-selection evidence

`audioPlayDump` on the exact firmware recorded:

```text
44100 PCM16, flags NONE         -> output 21, deep_buffer_out
44100 PCM_FLOAT, DEEP_BUFFER    -> output 21, deep_buffer_out
96000 PCM_FLOAT, DEEP_BUFFER    -> output 117, hifi_playback
44100 PCM16, DEEP_BUFFER        -> output 21, deep_buffer_out
```

This is reproducible from AOSP's local `selectOutput()` implementation. Its
score order is functional flags, channel compatibility, sampling rate,
performance flags, format, primary output, then first output. The sampling-rate
criterion is enabled only when the requested rate is greater than 48 kHz.

Therefore:

- at 96 kHz, HIFI's closer dynamic rate wins before DEEP_BUFFER is considered;
- at 44.1 or exactly 48 kHz, rate matching is skipped and the app's
  DEEP_BUFFER request wins.

That 48 kHz threshold is the framework reason ordinary low-rate tracks never
enter Xiaomi's HIFI lifecycle.

## Stock native HIFI chain is functional above 48 kHz

With a 96 kHz NetEase Float track on output 117, logs showed:

```text
HifiSampleRateManager: onPlaybackStarted: profile=hifi_playback, rate=96000
HifiSampleRateManager: Hardware update required: 384000 -> 96000
StreamHalAidl: [out|ioHandle:117] setParameters: sampling_rate=96000
```

The subsequent AudioFlinger dump showed the same MixerThread at 96000 Hz,
PCM32, routed to `AUDIO_DEVICE_OUT_USB_HEADSET`. This proves that the manager
does more than change the DAC display: the HAL change is read back into the
framework thread.

The dynamic HIFI output initially opens at its maximum 384 kHz. Xiaomi's native
manager can move the live stream to the active-track rate, but the AIDL FMQ
frame count is immutable after stream creation. QTI calculates 40 ms at the
initial rate, producing 15360 frames. After an in-place change that same buffer
is 320 ms at 48 kHz or about 348 ms at 44.1 kHz, so the initial profile choice
is a second, independent low-rate defect.

## Qualcomm's independent 44.1 kHz capability gap

The DAC descriptor advertises native 44.1 kHz, but this firmware's Qualcomm USB
helper exposes only seven preferred rates to HIFI:

```text
48000, 88200, 96000, 176400, 192000, 352800, 384000
```

The binary also contains a later 44100 priority entry. Swapping 44100 with the
352800 entry puts 44.1 inside the returned seven while preserving 352.8 in the
displaced slot. A policy-only route change cannot fix this omission.

## Xiaomi's existing `selectOutput` callback

At local VA `0x57200`, AOSP prepares:

```text
x0 = AudioPolicyManager
x1 = AudioPolicyClientInterface
x2 = AudioPolicyManager + 0x480  // current package String16
x3 = AudioPolicyManager + 0xa8   // mOutputs
x4 = frame + selected handle
bl AudioPolicyManagerStub::selectOutput
```

The implementation at `AudioPolicyManagerImpl::selectOutput()` is active, but
it is not a hidden HIFI whitelist. It checks Xiaomi AudioAppRegistry categories
such as CTS/deep-buffer bypass, may build `OutputSampleRate` parameters, and
contains an older client-migration path. Adding music packages to those
categories would activate unrelated behavior and is not the missing HIFI
selection rule.

The correct insertion point is immediately after this existing callback: keep
Xiaomi's result, then conditionally replace only the final handle.

## Exact object-layout evidence

The hook uses no C++ allocation or method call. Every field was independently
mapped from the device binaries:

| Object | Field | Offset/evidence |
|---|---|---|
| `SwAudioOutputCollection` | entry data / count | `+0x8 / +0x10`, 16-byte key/value items |
| collection item | handle / descriptor `sp<>` | `+0x0 / +0x8` |
| `SwAudioOutputDescriptor` | current `DeviceVector` | `+0xe8` |
| descriptor | `mProfile` | `+0x1d0`, confirmed in its constructor |
| `DeviceVector` | item data / count | `+0x8 / +0x10` |
| `DeviceDescriptor` | `audio_devices_t` | `+0x148` |
| `IOProfile` | libc++ name string | `+0x30` |

The profile-name access was also confirmed by Xiaomi's own descriptor dump:
it tests the libc++ short-string flag at profile `+0x30`, uses inline data at
`+0x31`, or loads the long-string pointer at `+0x40`.

Runtime scans are bounded to 64 outputs and 16 devices. Null pointers, empty
vectors, implausible counts, missing profiles, and unknown device types all
return the original selected handle.

## v0.7.0 routing rule

The hook first calls Xiaomi's original callback. It then checks:

```text
exact Apple/NetEase package
  AND original selected descriptor is currently USB-only
  AND a descriptor with mProfile->name == "hifi_playback" exists
  AND that HIFI descriptor is currently USB-only
    -> selected handle = HIFI handle
otherwise
    -> selected handle remains unchanged
```

`mProfile == nullptr` rejects duplicating outputs. Checking the current route
on both descriptors, instead of only checking that a DAC is attached, makes
Bluetooth and speaker selection fail closed even while USB remains connected.

## HIFI application filter

`HifiSampleRateManager::isAppAllowed(profile, app)` is a small exported thunk
to a larger body. The firmware's static strings include a QQ Music package,
which demonstrates that this is a real profile/package policy rather than a
generic permission check.

The v0.7.0 entry hook compares the profile first:

- for `hifi_playback`, only Apple Music and NetEase return true;
- every other profile replays the displaced `paciasp` and continues through
  Xiaomi's original body.

This avoids the older full-function replacement that accidentally changed
Deep Buffer and VoIP application policy too.

## HAL reconfiguration, dynamic-profile startup, and the 48 kHz boundary

The HIFI manager sends the standard `sampling_rate` parameter to the selected
output. Stock QTI admits only usecases 8 and 13 to the PAL connected-device
reconfiguration branch; this firmware's HIFI stream is usecase 3. A narrow
bitset patch adds only 3 while preserving 8 and 13. A previously installed
prototype of this instruction was found lingering in KernelSU's overlay cache,
which explained why a source tree that no longer contained the patch still
appeared to work on-device.

`HifiPlayback::getFrameCount()` independently calculates
`initialSampleRate * 40 / 1000`. Because the HIFI profile opens at 384 kHz,
AudioFlinger and the HAL create a 15360-frame / 122880-byte PCM32 FMQ. The later
vendor parameter changes PAL media configuration but cannot resize that queue.
A live 48 kHz dump still showed 15360 frames and roughly 448 ms thread-loop
write latency.

Changing only `getFrameCount()` is invalid. The resulting stream still declares
384 kHz while its queue holds only 1920 frames, so AudioFlinger and QTI no
longer agree on queue timing. The captured failure showed 184 FastMixer
underruns, 305 overruns, about 168 ms write latency, and `localSR` near 153 kHz
while the thread declared 384 kHz. Constant underruns produced severe pops.

The correct point is earlier, in APM's dynamic-profile open sequence. On USB
connection, `checkOutputsForDevice()` calls `openOutputWithProfileAndDevice()`
with both mixer and HAL configurations null. APM probes the HAL, imports the
dynamic profiles, calls `IOProfile::pickAudioProfile()`, and reopens with the
chosen PCM32 stereo configuration. The generic picker selects 384 kHz here.
Immediately after that picker, the exact profile pointer and selected
`audio_config_t` are both live. Restricting only `hifi_playback` to a 48 kHz
initial sample rate preserves its chosen format/channel mask and causes QTI's
stock frame calculation to allocate 1920 frames naturally.

AudioFlinger's local HIFI parameter path contains:

```asm
ldr w8, [MixerThread, #currentSampleRate]
cmp w8, #48000
b.hi readOutputParameters_l
```

The stock condition covers a high-rate transition such as 384 -> 96, but not a
thread already at 44.1 or 48. The one-instruction patch makes this branch
unconditional inside that existing HIFI synchronization path, allowing the
MixerThread to adopt both 44.1 -> 48 and 48 -> 44.1 HAL changes. The same path
calls `PlaybackThread::readOutputParameters_l(true)`, constructs a new
AudioMixer at the accepted output rate, and recreates the existing track mixer
slots. Thus a single active source-rate track, MixerThread and PAL can converge
after each native rate event; simultaneous tracks at different rates still
require SRC by definition.

## Android 16 Pudding HAL port

Pudding and Nezha use the same Android 16 / SM8850 / QTI AIDL generation, but
their C++ object layouts are not ABI-compatible. Nezha embeds its
`AudioPortConfig`; Pudding stores pointers to both `AudioPortConfig` and a
cached PAL attribute block. Copying the Nezha handler or vtable would therefore
write into unrelated Pudding state.

The apparent missing `HifiPlayback` class does not need to be transplanted.
Its only Nezha symbol is a static `getFrameCount()` helper, and its 40 ms frame
calculation is identical to Pudding's existing `DeepBufferPlayback` helper.
QTI's public AIDL source and Pudding's machine code both map an output with no
flags to `DEEP_BUFFER_PLAYBACK` (usecase 3), matching Pudding's flagless
`hifi_playback` policy port.

What Pudding actually compiled out is the `sampling_rate` block in
`MiStreamOutPrimary::setVendorParameters()`. The Pudding-specific payload:

- accepts only 44.1/48 kHz families through 352.8/384 kHz;
- updates cached PAL sample rate at `+0x40`;
- sets `AudioPortConfig.sampleRate` value at `+0x8` and its discriminator at
  `+0xc`;
- for live usecase 3 only, uses Pudding's own configure mutex and concrete
  `standby()`; and
- returns to the stock parameter destruction and status path.

The payload lives in a linker-owned executable zero gap whose owner call,
geometry and emptiness are verified before use. The hook, object fields, PLT
calls and concrete standby symbol are resolved from semantic signatures at
installation time. Pudding and Nezha OTA libraries both pass two-pass offline
idempotence tests, while a deliberately mixed Pudding layout fails closed.

### Popsicle variant

Xiaomi 17 Pro Max (`popsicle`) Android 16 is a hybrid of the two recorded
baselines. Its policy manager, policy components and Xiaomi policy
implementation are byte-identical to Nezha Android 16; its Qualcomm USB library
and audio HAL service are byte-identical to Pudding. AudioFlinger and the core
QTI HAL have separate Build IDs.

The distinct core HAL still resolves every Pudding-specific pointer-layout
anchor: `AudioPortConfig*`, cached PAL attributes, configure mutex, sample-rate
field/discriminator, usecase tag, PAL handle and the linker-owned executable
gap. Its flagless ODM `hifi_playback` port maps to Deep Buffer usecase 3 and it
also lacks the static `HifiPlayback` helper. The correct adaptation is therefore
the Pudding-family `sampling_rate` handler combined with the common semantic
policy/MixerThread/USB patches. Two-pass offline application is byte-idempotent;
hardware behavior remains unverified.

## Idle 384 kHz retention

Live `0.7.3-alpha` logs exposed a separate Xiaomi lifecycle defect. After the
last real HIFI application stopped, `updateLatestMaxStrategy()` correctly
reported that all applications were stopped, but `getActiveSampleRate()` still
returned 384 kHz from a retained synthetic/default rate-tree node. The manager
then sent `sampling_rate=384000` to the idle HIFI output. An ordinary 48 kHz
Deep Buffer client could consequently appear as a 48 kHz Mixer source attached
to a temporarily 384 kHz USB sink.

The idle gate therefore mirrors Xiaomi's existing
`areAllApplicationsStopped()` semantics: it scans the native application-count
list at `ProfileManager + 0x50`. If no node has a positive count it returns
48 kHz, regardless of retained rate-tree nodes. If a real application remains,
the original LATEST_MAX tree lookup runs unchanged. This adds no counter,
polling or cross-profile ownership state.

## Final transport safety gate

`sendkeySamplingRateToAHal(output, rate)` otherwise trusts the output handle.
The sender hook resolves that exact handle in `mOutputs` and accepts the write
only when every currently routed device is one of:

- `AUDIO_DEVICE_OUT_USB_ACCESSORY`;
- `AUDIO_DEVICE_OUT_USB_DEVICE`;
- `AUDIO_DEVICE_OUT_USB_HEADSET`.

Empty, unknown, Bluetooth, speaker, wired, and mixed routes return without
sending the parameter. A zero rate follows the stock zero-rate path.

## Why the previous architecture was rejected

Preferred Mixer caused output reopen/reuse behavior and a 384 kHz recovery
loop on this Android 17 baseline. Deep Buffer adaptation then required a second
profile lifecycle, HAL usecase modifications, XML edits and cross-profile
arbitration. Repeated transitions eventually produced multiple rate requests,
dead USB output and playback stalls.

The v0.6.8 `startOutput` late-bootstrap hook was additionally incorrect at the
machine-code level: it entered a live hot path with wrong register/control-flow
assumptions and caused an audioserver crash loop. It is removed, not papered
over with a retry or watchdog.

## Why `BIT_PERFECT` is not the first fix

Android 17's official bit-perfect behavior is a separate contract between an
AIDL HAL, a flagged output profile, preferred mixer attributes and an app that
requests them. Merely adding the flag does not change the default
`selectOutput()` rule that sends ordinary 44.1/48 kHz DEEP_BUFFER tracks away
from HIFI.

On this firmware, forcing the flag also selected a separate Qualcomm bit-perfect
usecase that did not configure successfully and repeatedly reopened. The safe
order is:

1. prove deterministic sample-rate following on Xiaomi's already-functional
   HIFI MixerThread;
2. verify PCM container, effects and volume behavior;
3. only then evaluate the stricter bit-perfect usecase as a separate change.

## Review of the two external `AndroidBitPerfect` prototypes

The supplied archives implement one split prototype, not a HAL patch:

```text
LSPosed/Vector hook in each player
  -> intercept every Java AudioTrack constructor
  -> exported ContentProvider in a companion APK
  -> AudioManager.getSupportedMixerAttributes(USB)
  -> require an exact MIXER_BEHAVIOR_BIT_PERFECT AudioFormat
  -> setPreferredMixerAttributes(USAGE_MEDIA, USB, profile)

Magisk shell module
  -> property switch + FIFO observer + state file + bpctl
```

Its strongest reusable idea is observing the final `AudioFormat` requested by
an application. It cannot supply a missing mixer profile or repair Xiaomi's
44.1/48 kHz output selection. On this firmware the existing HIFI port is not a
working advertised bit-perfect profile, and the earlier forced flag selected a
separate QTI usecase that failed to configure and reopened repeatedly.

The prototype is also deliberately not imported into this module because:

- it hooks every declared Java `AudioTrack` constructor, including constructor
  chaining, without a re-entry guard;
- every accepted constructor increments a separate `trackCount`, while cleanup
  depends on an explicit Java `AudioTrack.release()` hook;
- each acquisition starts a `getprop` subprocess and performs cross-process
  Provider calls before constructing the track;
- its exported Provider has no caller permission or package-to-UID validation,
  so an unrelated process can become the first session owner;
- its root half runs a persistent FIFO loop, and its own handoff notes say that
  reader was not reliably resident on the tested device;
- it still depends on Preferred Mixer output reopen/invalidation behavior—the
  exact lifecycle that was unstable in the Xiaomi experiments.

AOSP's
[preferred-mixer documentation](https://source.android.com/docs/core/audio/preferred-mixer-attr)
confirms this boundary: bit-perfect mixer behavior is optional, AIDL-only, and
requires a dynamic USB mix port flagged `AUDIO_OUTPUT_FLAG_BIT_PERFECT`.
The HAL must then guarantee no scaling, SRC, effects, or DSP mixing. Preferred
mixer requests are UID-owned according to the
[policy-service interface](https://android.googlesource.com/platform/frameworks/av/+/refs/heads/main/media/libaudioclient/aidl/android/media/IAudioPolicyService.aidl)
and can reopen an output when the selected format does not match. Therefore the
prototype is a potentially useful future probe, but it is not a solution for
the present low-rate routing defect and does not prove bit identity by itself.

## Unresolved cross-application lifecycle

Same-app HIFI overlap can use Xiaomi's existing `LATEST_MAX` per-rate counts.
The harder case is a Deep Buffer track already active before a selected HIFI
app starts, or a normal app starting while HIFI remains active. Those are two
logical output descriptors driving one physical USB backend.

v0.7.0 does not claim to solve takeover/restoration. A correct solution needs
evidence for native client migration or a single-output lifecycle that observes
both starts and stops. Reintroducing an external daemon or the rejected shared
counter hook would hide the unresolved ownership problem rather than solve it.
