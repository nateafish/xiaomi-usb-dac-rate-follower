# Xiaomi 15 Dada / Android 16 audio-stack revalidation

This note is scoped to `OS3.0.305.0.WOCCNXM`. It separates facts verified in
the extracted firmware from behavior that still needs hardware traces.

## What this module is supposed to do

The module is a source-rate follower. For one active PCM media track on the
USB HIFI output, its target invariant is:

```text
AudioTrack source rate
  -> Xiaomi HifiSampleRateManager event rate
  -> sampling_rate=<the same integer>
  -> QTI stream AudioPortConfig / PAL requested rate
  -> exact USB endpoint rate when the DAC advertises it
```

It must not multiply 44.1 kHz into 352.8 kHz, perform software SRC, or infer a
rate from catalog metadata. Multiple simultaneous source rates necessarily
require arbitration or mixing and are outside the single-track invariant.

## AIDL v2 is not the seven-rate limit

The device VINTF manifest declares `android.hardware.audio.core` version 2 for
the default and USB modules. AOSP represents an audio profile's sample rates as
an AIDL `int[]`; the interface does not impose a seven-entry maximum.

The seven-entry maximum comes from AudioReach PAL instead:

```text
MAX_SUPPORTED_SAMPLE_RATES = 7
dynamic_media_config.sample_rate[MAX_SUPPORTED_SAMPLE_RATES + 1]
```

The extra element is the zero terminator. Xiaomi 15's `libar-pal.so` contains
the same 7-item cap in `USBCardConfig::readSupportedSampleRate()`.

## PAL has a 15-rate parser and a 7-rate report

`USBDeviceConfig::supported_sample_rates_` is a 60-byte table, not a nine-item
table:

```text
384000 352800 192000 176400 96000 88200 64000 48000 44100
32000 24000 22050 16000 11025 8000
```

`getSampleRates()` walks all 15 entries and records every descriptor match in
the per-configuration `rates_` vector and a bit mask. `readSupportedSampleRate()`
then enumerates the lowest set bits and copies at most seven values into the
legacy PAL dynamic-media structure.

This distinction matters: the internal USB selector can retain more rates than
the framework-facing capability list. `getBestRate()` returns the requested
rate unchanged when it is present in `rates_`; only an unsupported request
enters its same-family/nearest-rate fallback.

## Meaning of the 44.1 / 352.8 table swap

On a DAC advertising the eight common 44.1/48 kHz-family rates, stock priority
reports:

```text
384000 352800 192000 176400 96000 88200 48000
```

and omits 44100. Swapping the positions of 44100 and 352800 reports:

```text
384000 44100 192000 176400 96000 88200 48000
```

and omits 352800 from the framework-facing seven. Because the same table is
used to build and decode the mask, this swap does not convert a 44100 request
to 352800. It is a capability-priority tradeoff. Treating it as support for all
eight rates would be incorrect.

## Xiaomi's native owner and Dada's missing consumer

The system policy binary contains Xiaomi's complete `HifiSampleRateManager`:

- USB connection builds the dynamic `hifi_playback` profile from the reported
  device rates;
- `startOutput()` passes the client descriptor's actual sample rate to
  `onPlaybackStarted()`;
- the `LATEST_MAX` profile strategy tracks active source-rate counts; and
- the hardware callback sends `sampling_rate=<selected rate>` to the output.

Dada's QTI `MiStreamOutPrimary::setVendorParameters()` does not contain the
`sampling_rate` parser present on other Xiaomi/QTI generations. The adaptation
therefore has to restore this missing consumer while preserving the stock
worker lifecycle: record the requested `AudioPortConfig` rate, enter standby
on the transfer worker, and let the following stock transfer call configure
PAL again.

The parameter trampoline preserves the stock parser's live `x1/x2` key and
buffer registers in its own aligned stack frame before calling any helper. The
worker trampoline likewise uses a private frame and runs before the stock
transfer path acquires or mutates stream state. A compatible OTA must resolve
all semantic signatures and object layouts again; whole-file hashes remain
diagnostic rather than installation gates.

The current worker port is structurally verified offline, but the complete
44.1/48/88.2/96/176.4/192/384 transition matrix has not been observed on
Xiaomi 15 hardware. Installation therefore requires the theoretical-target
warning and physical confirmation until logs prove that source rate, manager
decision, HAL request, PAL rate and DAC indication agree for that supported
set, including consecutive transitions, and that an explicit 352.8 kHz request
is rejected without mutating stream state.

## Primary references

- AOSP `AudioProfile.aidl`: <https://android.googlesource.com/platform/frameworks/base/+/45efd8a9d590a94e4f729afb9fc969c6a3bd3921/media/aidl/android/media/audio/common/AudioProfile.aidl>
- AOSP AIDL dynamic USB/HIFI profile behavior: <https://android.googlesource.com/platform/hardware/interfaces/+/refs/heads/main/audio/aidl/default/Module.cpp>
- AudioReach PAL structure capacity: <https://github.com/AudioReach/audioreach-pal/blob/88ad5461a87735124c2daa321a114c5806445e4b/inc/PalDefs.h#L617-L626>
- AudioReach USB capability truncation: <https://github.com/AudioReach/audioreach-pal/blob/88ad5461a87735124c2daa321a114c5806445e4b/device/USBAudio/src/USBAudio.cpp#L815-L842>
- AudioReach 15-rate parsing and exact-rate selection: <https://github.com/AudioReach/audioreach-pal/blob/88ad5461a87735124c2daa321a114c5806445e4b/device/USBAudio/src/USBAudio.cpp#L1011-L1194>
