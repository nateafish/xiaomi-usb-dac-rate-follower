# Android 17 Preferred Mixer failure analysis

This note separates two failures that previously looked like one Qualcomm
`BIT_PERFECT_PLAYBACK` problem.

## Audioserver null dereference

The captured tombstone is exact:

```text
SIGSEGV, fault address 0xe0
AudioPolicyManager::reopenOutput(...) + 88
AudioPolicyManager::setPreferredMixerAttributes(...) + 3712
```

At `reopenOutput+0x58` (`VA 0x80bb8`) the firmware executes:

```asm
ldr x8, [x20]       // sp<SwAudioOutputDescriptor>::get()
ldr w1, [x8,#0xe0]  // mIoHandle; crashes when x8 == 0
```

The matching Android 17 source constructs `outputsToReopen` as a vector and
pushes `output->mIoHandle` once for every active client owned by the requesting
UID and product strategy. It does not deduplicate the handle. If two matching
tracks are active on one output, the first loop iteration closes and replaces
that output. The second iteration calls `mOutputs.valueFor(oldHandle)`, gets a
null descriptor, and passes it directly to `reopenOutput()`.

The three captured audioserver deaths have the same PC, registers, fault
address, and caller. This makes repeated Preferred Mixer writes while an app
has overlapping tracks unsafe on this firmware. A module must install one
preference before the first target track, preserve the object for the same UID,
and never update it per track. A defensive APM patch should additionally
deduplicate or null-check this reopen list before official Bit Perfect is
considered.

## Why the post-crash loop selected 384 kHz

After repeated audioserver deaths, the trace shows a different failure:

```text
source AudioTrack: 44100 Hz / PCM16 / DEEP_BUFFER
hifi_playback output: 384000 Hz / PCM32 / BIT_PERFECT
getOutputForAttr selects that existing hifi output
startSource: fails as there is bit-perfect playback active
close/reopen/restoreTrack repeats
```

The 384 kHz value is not a conversion selected for the 44.1 kHz track. It is
the dynamic HIFI profile's default reopening choice after state loss. AOSP
opens a dynamic profile without an explicit HAL configuration, asks the
profile to `pickAudioProfile()`, and this firmware chooses its highest exposed
PCM32 stereo rate. The source track therefore does not match the existing
output configuration, so `getOutputForAttrInt()` does not add the
`AUDIO_OUTPUT_FLAG_BIT_PERFECT` client flag. The track is then rejected from an
already Bit Perfect output and its restore path repeats indefinitely.

This explains why merely adding `BIT_PERFECT` to the empty dynamic
`hifi_playback` mixPort is not safe. The profile also needs a deterministic
default/recovery configuration, the Preferred Mixer reopen bug must be fixed,
and the player must create a track whose requested configuration matches the
preference. The current module deliberately keeps HIFI unflagged and uses
DEFAULT mixer behavior.

## Consequence for the native rate follower

HIFI and Deep Buffer are two logical outputs but one physical USB backend.
Xiaomi's current manager calculates each profile independently, so the last
allowed profile event can leave the shared backend stale. The required native
policy is:

```text
no selected HIFI activity       -> 48000
selected HIFI, no Deep activity -> highest active HIFI rate
selected HIFI plus Deep         -> highest active Deep rate
Deep stops, HIFI remains        -> restore highest active HIFI rate
```

Both profiles already maintain balanced per-rate counts. The missing piece is
a single final arbitration point before `sampling_rate=<rate>` is sent to the
HAL. No package polling, playback daemon, or catalog metadata is required.
