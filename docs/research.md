# Xiaomi Android 17 USB rate-following research

## Conclusion

The tested firmware already contains almost the entire native rate-following
implementation. The missing behavior is not a single USB XML declaration:

```text
allowed app AudioTrack starts/stops
        ↓
Xiaomi HifiSampleRateManager counts active source rates
        ↓
ProfileManager chooses a hardware rate
        ↓
AudioPolicyManager sends sampling_rate=<rate> to the output HAL
        ↓
QTI AIDL HAL / PAL changes the USB backend
        ↓
AudioFlinger MixerThread must read back and adopt the HAL rate
```

The v0.6.5 design repairs this existing chain. It does not create a second state
machine or repeatedly inspect playback from userspace.

## Where configuration lives

This is a Qualcomm AIDL Audio HAL device. Relevant device paths include:

- `/vendor/bin/hw/audiohalservice.qti`
- `/vendor/lib64/hw/libaudiocorehal.qti.so`
- `/vendor/lib64/libaudioaidlcommon.so`
- `/vendor/lib64/libdev_usb.so`
- `/vendor/etc/init/audiohalservice_qti.rc`
- `/vendor/etc/vintf/manifest/manifest_audiocorehal_default.xml`
- `/vendor/etc/audio/audio_module_config_primary.xml`
- `/odm/etc/audio/audio_module_config_primary.xml`
- `/system/lib64/libaudiopolicymanagerdefault.so`
- `/system/lib64/libaudioflinger.so`
- `/system_ext/lib64/libaudiopolicymanagerimpl.so`

Configuration therefore exists in several forms:

- XML describes mix ports, profiles, routes, flags, and dynamic capabilities.
- The QTI AIDL HAL translates PAL USB capabilities into framework profiles.
- PAL/vendor code parses descriptors and selects the real endpoint format.
- Xiaomi's system AudioPolicyManager extension carries app whitelist, profile
  strategy, active-track counts, and the HAL `sampling_rate` callback.
- AudioFlinger carries the live MixerThread/HAL synchronization logic.

## Xiaomi HifiSampleRateManager

Reverse engineering of the exact system policy library found:

- three built-in profile configurations: `deep_buffer_out`, `hifi_playback`,
  and `voip_playback`;
- built-in whitelist originally containing WeChat and QQ;
- `onPlaybackStarted()` and `onPlaybackStopped()` lifecycle integration;
- per-rate active application counts;
- `FIRST_LOCK` and `LATEST_MAX` strategies;
- `triggerHardwareSampleRateUpdate()`;
- `sendkeySamplingRateToAHal()`, which sends `sampling_rate=<rate>` to the
  selected output.

The firmware property `ro.vendor.audio.hifi.config=13` enables Xiaomi features
6, 7, and 9. Feature 7 is the important AudioFlinger Hifi synchronization path.

The three static records are 0x58 bytes each. Their important fields are the
name at +0x0, strategy at +0x8, default sample rate at +0xc, and optional
device type at +0x28. `hifi_playback` already has `LATEST_MAX` and USB device
type `0x04000000`, but its default sample rate is zero. The existing
`checkOutputsForDevice()` USB path compares the IOProfile name with
`hifi_playback` and calls `createHifiProfile()`; that function loads +0xc and
exits at `0xd4114` when it is zero, logging `sample rate cannot be 0`.

v0.6.5 changes that HIFI default to 48000 while the static records are being
constructed. It also changes only Deep Buffer's static strategy from
`FIRST_LOCK` to `LATEST_MAX`. The common `ProfileManager::initialize()` call
continues to load each record's strategy, so VoIP is not changed.

Feature 6 constructs `HifiSampleRateManager`, but Deep profile creation in
`AudioPolicyManager::initialize()` has a second Feature 8 check. At file offset
`0xc3260`, stock exits before calling `createHifiProfile("deep_buffer_out")`.
v0.6.5 replaces only that early-exit instruction with a NOP. It does not change
the property to 15 and does not globally enable Feature 8's effect handling.

## Package-specific HIFI routing through Preferred Mixer

The active AIDL policy exposes `hifi_playback` as an unflagged, dynamic,
USB-only output profile. AOSP's `setPreferredMixerAttributes()` can select such
a dynamic profile with `AUDIO_MIXER_BEHAVIOR_DEFAULT`; BIT_PERFECT is not
required. The standard output-selection path opens that profile for the owning
UID, while other UIDs ignore the preference.

Immediately before the firmware's existing preferred-attribute lookup,
`getOutputForAttrInt()` has the resolved attributes, selected USB port, product
strategy, and UID. The outer `getOutputForAttr()` stores the resolved package
as a `String16` at `AudioPolicyManager+0x480` under the policy lock.

The v0.6.5 hook acts only for MEDIA on a selected USB accessory/device/headset
type and an exact UTF-16 Apple Music or NetEase package. It intentionally does
not compare framework port IDs, which are assigned dynamically when a DAC is
attached. It queries the current preferred
object and reads its owner UID at +0x14. The same UID reuses the object, so
repeated AudioTracks do not reset active-client counts. A missing owner, or a
real switch between the two whitelist UIDs, installs one 48000/stereo/PCM32
preference with DEFAULT behavior.

That fixed format is only a HIFI bootstrap. On `startOutput()`, Xiaomi reads
the AudioTrack rate from its client descriptor and calls
`onPlaybackStarted(profile, uid, sampleRate)`; the existing LATEST_MAX/event
counter sends the real rate to the HAL. `stopOutput()` provides the matching
lifecycle event. The hook is 374 bytes in a verified zero-filled executable
cave and allocates no persistent writable state.

### Why FIRST_LOCK fails gapless playback

Apple Music and similar players prepare the next AudioTrack before the old song
is fully stopped. With `FIRST_LOCK`, the first active 44.1 kHz track owns the
hardware rate and a newly started 48/96 kHz track cannot replace it. This
matches the observed stale 44.1 kHz output and speed errors.

`LATEST_MAX` uses the active rate counts already maintained by Xiaomi. During
overlap, the highest active rate wins; after the old high-rate track stops, the
lower new rate becomes eligible. This is deterministic and event-driven.

## Deep Buffer's ordering defect

Static analysis of `HifiSampleRateManager::handlePlaybackEvent()` found an
important limitation in Xiaomi's inherited Deep Buffer implementation. The
function updates the profile's per-rate application count first, and only then
checks the active effect and calls `isAppAllowed()`:

```text
start/stop event
    -> updateFirstLockStrategy() or updateLatestMaxStrategy()
    -> calculate candidate active rate
    -> Deep Buffer effect gate
    -> isAppAllowed(profile, current app)
    -> optionally triggerHardwareSampleRateUpdate()
```

Consequently, a non-whitelisted application can change Deep Buffer's internal
rate counts even though its start event is later denied permission to update
the HAL. A subsequent allowed-app event can then make a decision from those
changed counts. This explains the observed class of failures where another app
starts at 48 kHz, the USB backend does not switch immediately, and the allowed
44.1 kHz app does not reliably regain its rate afterward.

This is not evidence that reference counting itself is unnecessary. Balanced
start/stop counts are how the native code handles gapless overlap. The defect is
that the permission decision and the count/update decision are not one atomic
policy for Deep Buffer on this migrated baseline.

`hifi_playback` avoids most of this pollution because Preferred Mixer routes
only the selected owner UID to that IOProfile. It does not by itself solve the
case where a normal Deep Buffer stream and the HIFI stream are simultaneously
active against one physical USB backend. v0.6.5 deliberately treats all active
Deep counts as temporary backend ownership while selected HIFI exists, then
returns to the HIFI maximum when Deep becomes empty. This still requires the
on-device concurrency matrix before it can be called production-safe.

### Stale stop-package state

`onAppChanged(name, rate, starting)` stores the latest start package at manager
offset `+0x160`, the latest stop package at `+0x178`, and package/rate history
at `+0x190`. The later playback handler always copies `+0x160`, including on a
stop event; it never reads `+0x178`. This is a concrete inherited defect, not a
timing guess. It can make a stop decision appear to belong to the most recent
starter.

The v0.6.5 arbiter does not use either last-package string. Package scope is
established by routing the selected UID to HIFI, while balanced native profile
counts determine shared-backend ownership. This avoids adding a second package
tracker and avoids relying on Xiaomi's stale stop field.

## The older system_ext `selectOutput()` path

`/system_ext/lib64/libaudiopolicymanagerimpl.so` also contains an older dynamic
output migration path. `AudioPolicyManagerImpl::selectOutput()` can detect a
sample-rate mismatch, build `OutputSampleRate=<rate>;add_track=<rate>`, send it
to the current output, transfer clients, and reroute the descriptor.

This path is active: the AOSP-side `AudioPolicyManager::selectOutput()` calls
the vendor stub after ordinary output selection. It is not, however, a generic
music rate follower. Its decisive mask bit is produced by
`getAppMaskByNameImpl()` from app category 21, which this firmware's registry
maps to `karaoke_input_source`. The nearby `deep_buffer_bypass` category only
controls `ro.vendor.audio.ce.bypass`; it does not enable sample-rate following.
Adding Apple Music or NetEase to `deep_buffer_bypass` would therefore patch the
wrong subsystem.

The related `dynamic_audio_usecase_pkg` string belongs to
`setAppNameParameter()` and is sent for category 43 (`short_video`). It is also
not the missing general USB music whitelist.

These findings leave Xiaomi's `HifiSampleRateManager` as the correct native
base for this project, while the older `selectOutput()` implementation remains
useful evidence for how Xiaomi previously migrated clients without a userspace
daemon.

## HAL reconfiguration is in-place, not APM reopen

`AudioPolicyManager::sendkeySamplingRateToAHal()` constructs the standard
`sampling_rate` parameter and calls `AudioPolicyClientInterface::setParameters`
for the selected output. It does not call AOSP `reopenOutput()`.

In `MiStreamOutPrimary::setVendorParameters()`, QTI parses that rate, updates
the stream's internal `AudioPortConfig`, places HIFI (usecase 13) and VoIP
(usecase 8) into standby, and lets the next write run
`MiStreamOutPrimary::configure()` through PAL. The v0.6.5 HAL patch extends that
same existing standby path to Deep Buffer (usecase 3). AudioFlinger's
`readOutputParameters_l(true)` then synchronizes the MixerThread with the rate
actually adopted by HAL.

This confirms that the intended vendor chain is an in-place stream
reconfiguration. Replacing it with unconditional APM close/reopen would be a
different state machine and carries the same dead-output and repeated-open
risks observed in earlier prototypes.

## AudioFlinger’s hidden 48 kHz boundary

`MixerThread::checkForNewParameter_l()` in the exact `libaudioflinger.so`
contains the decisive condition:

```asm
1b0a78  ldr w8, [x28,#0x304]   // MixerThread current sample rate
1b0a7c  mov w9, #48000
1b0a80  cmp w8, w9
1b0a84  b.hi 0x1b0c2c
```

At `0x1b0c2c`, feature 7 eventually calls:

```text
PlaybackThread::readOutputParameters_l(true)
```

That method queries the HAL's actual output parameters, updates MixerThread's
sample rate, and recalculates minimum frame count, buffers, and tracks. Xiaomi's
own strings include `HIFI: readOutputParameters_l mSampleRate:%d`.

Stock therefore synchronizes only when the *current* mixer rate is above 48
kHz. Both 48 → 44.1 and 44.1 → 48 skip the call. Replacing `b.hi` with the same
function's unconditional branch enables Xiaomi's original in-place update for
the missing low-rate boundary. It avoids closing the output, returning
`DEAD_OBJECT`, restoring AudioTracks, or duplicating Hifi reference counts.

## Xiaomi's disconnected effect state

`HifiSampleRateManager::handlePlaybackEvent()` special-cases
`deep_buffer_out`. Its effect enum is Dolby=0, MiSound=1, None=2, Unknown=3.
Stock continues only for exactly None=2; every other value logs
`deep_buffer with active effect, skipping sample rate management` and returns
before its app allow check.

The v0.6.1 live capture proved the USB path itself was ready: NetEase's
`TrackClientDescriptor` carried 44100 Hz, the dynamic USB profile contained
44100 Hz, and AudioFlinger's USB `AudioOut_15` thread had zero effect chains.
The device declaration is also unambiguous:
`persist.audio.effect.device_map=...;usb_device:none`.

This property is where the captured “Original sound” state is actually visible
for USB: the endpoint maps to `none`, while the speaker maps to `dolby` and
`persist.vendor.audio.misound.disable=true`. It is an effect-routing declaration,
not a sample-rate capability declaration. The separate HIFI feature file paths
embedded in Xiaomi's policy extension are `/vendor/etc/AudioFeatureConfig.xml`
and `/data/system/audio/AudioFeatureConfig.xml`; neither file was present in the
offline archive, so their live contents remain a read-only capture item rather
than an assumption in the module.

The disconnect is inside policy. The Hifi manager constructor writes Unknown=3
to its independent field at object offset `0x158`. `setProParameters()` can
forward `activeEffect` to `onEffectChanged()`, but only when both Hifi Feature 6
and Feature 8 are enabled. This firmware initializes the manager through
Feature 6 while its configuration leaves Feature 8 disabled, so Unknown can
remain stale even though the selected USB effect is None.

At exact file offset `0xd55b4`, v0.6.5 changes `b.eq` to unsigned `b.hs`.
The branch now accepts both None=2 and Unknown=3, while still rejecting
Dolby=0 and MiSound=1. Its target remains the original continuation at
`0xd55e0`, which executes `isAppAllowed()`; only Apple Music and NetEase pass.
This is narrower than an unconditional bypass and adds no polling or daemon.

## Why the Qualcomm USB capability patch remains necessary

The DAC descriptor and ALSA endpoint advertise native 44.1 kHz, but QTI PAL's
dynamic capability ABI returns only seven rates plus a zero terminator. On this
firmware, 44.1 kHz is the eighth matching priority and disappears from the AIDL
USB profile. A clean v0.6 boot without the vendor micro-patch confirmed that
AudioPolicy exposed only `48000, 88200, 96000, 176400, 192000, 352800, 384000`.

The guarded `libdev_usb.so` patch swaps two uint32 priorities:

```text
0x7160: 352800 -> 44100
0x717c:  44100 -> 352800
```

This preserves the seven-entry ABI and makes the framework/Hifi manager see
44.1 kHz. It does not fill the zero terminator or scan beyond the array.

## Selective package handling

The exported `HifiSampleRateManager::isAppAllowed(profile, app)` thunk has one
direct internal implementation. v0.6.5 replaces that implementation with a
196-byte PAC-compatible function that:

- preserves the stock prologue and epilogue addresses for unwind compatibility;
- decodes Android libc++ short and long `std::string` representations;
- accepts exact package names only;
- embeds no writable state and performs no allocation or external call.

The function was compiled with NDK 29 and run as an arm64 test executable on
the target phone. Apple Music and NetEase returned true; WeChat, QQ, truncated,
extended, and empty names returned false.

## Why this is not a strict Float/bit-perfect claim

The QTI USB path on this device uses PCM32 as the mixer/HAL format. Float is not
a supported final USB HAL format. A Float or narrower integer source can be
converted by normal AudioFlinger processing into PCM32 while preserving the
requested sample rate. Rate following and strict bit identity are separate:
effects, normalization, software volume, app DSP, or Float conversion can still
change sample values.

## AOSP paths to inspect

- `frameworks/av/services/audiopolicy/managerdefault/AudioPolicyManager.cpp`
  - `startOutput()` / `stopOutput()`
  - `setParameters()` and output reopen behavior
- `frameworks/av/services/audioflinger/Threads.cpp`
  - `MixerThread::checkForNewParameter_l()`
  - `PlaybackThread::readOutputParameters_l()`
- `frameworks/av/media/libaudioclient/AudioTrack.cpp`
- `system/media/audio/include/system/audio.h`
- `hardware/interfaces/audio/aidl/default/`

## Preferred Mixer crash and 384 kHz recovery loop

The failed Bit Perfect prototype exposed two independent framework defects.
The captured audioserver tombstone dereferences a null output descriptor in
`reopenOutput()` from `setPreferredMixerAttributes()`. Android 17 adds the same
output handle to a vector once per matching active client; overlapping tracks
can therefore close the handle on the first iteration and look it up again on
the second. The exact analysis is recorded in
[`android17-preferred-mixer-failure.md`](android17-preferred-mixer-failure.md).

After those deaths, `hifi_playback` reopened at the dynamic profile's chosen
384 kHz PCM32 default while the restored source track requested 44.1 kHz
PCM16. Because the configurations did not match, the client did not receive
the Bit Perfect flag, `startSource()` rejected it from the already Bit Perfect
output, and AudioTrack restoration created the observed close/open loop.

This is why v0.6.5 neither writes a Preferred Mixer preference per track nor
marks the dynamic HIFI profile Bit Perfect. A future official Bit Perfect mode
must first guard the duplicate reopen list and define deterministic dynamic
profile recovery behavior.

## Shared USB backend arbitration

Deep Buffer and HIFI keep independent rate counters but drive one physical USB
backend. The target native behavior is now specified by
[`tests/rate_arbiter_model.py`](../tests/rate_arbiter_model.py): Deep playback
temporarily wins while a selected HIFI package is active, stopping the last
Deep track restores the still-active HIFI rate, and absence of selected HIFI
activity returns policy to 48 kHz. The model also requires duplicate same-rate
tracks to produce no redundant HAL writes.

The binary exposes enough existing state to implement this without a daemon:
each `ProfileManager` owns its active-rate count tree and current maximum, and
the hardware callback already centralizes `sampling_rate=<rate>`. The v0.6.6
hook at `0xd57bc` replaces that callback decision. Its 440-byte cave routine
looks up both profiles under the manager's existing shared lock, summarizes
their native count maps, and forces reevaluation only on a local maximum change
or a first/last cross-profile ownership boundary.

## Why Bluetooth needs a final sender-side gate

Xiaomi's `handlePlaybackEvent()` checks the manager's current-device set for
speaker in one branch, but does not exclude Bluetooth. The centralized
`AudioPolicyManager::sendkeySamplingRateToAHal(output, rate)` callback then
constructs `sampling_rate=<rate>` and calls `setParameters()` on the supplied
output handle without any routed-device check. This explains the observed
Bluetooth speed change: package selection and rate counting can reach the same
vendor callback after the destination is no longer USB.

v0.6.6 branches from `sendkeySamplingRateToAHal()+4` into a 140-byte,
allocation-free gate. It resolves the exact output handle through
`AudioPolicyManager::mOutputs`, reads that descriptor's current `DeviceVector`,
and accepts only `AUDIO_DEVICE_OUT_USB_ACCESSORY`, `_USB_DEVICE`, and
`_USB_HEADSET`. Every listed device must be USB. Bluetooth, speaker, wired,
mixed, empty, null, and unknown routes return before the original function
signs its stack or calls the HAL; the accepted path resumes at the original
`paciasp` instruction.

This is stricter than checking whether any USB DAC is attached and fails
closed if an internal object layout cannot be resolved. The installer verifies
the exact output-collection item stride, `SwAudioOutputDescriptor` current-
device offset, and `DeviceDescriptor` type offset in
`libaudiopolicycomponents.so` before installing the policy patch.

The strongest evidence for this build is the exact on-device binary and live
HAL trace; AOSP explains the surrounding standard behavior, while the Xiaomi
feature gates and 48 kHz condition are vendor modifications.

## KernelSU mounting

KernelSU 3+ delegates system overlays to one active metamodule. The test phone
now uses official `meta-overlayfs 1.3.1`; `/data/adb/metamodule` points to it and
its ext4 content image mounts successfully. v0.6.6 intentionally refuses a
KernelSU installation without an active metamodule and contains no custom bind
fallback.
