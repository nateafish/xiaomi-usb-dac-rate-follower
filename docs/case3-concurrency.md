# Usecase-3 reconfiguration and transfer concurrency

## Result

The connected Xiaomi 17 Pro Android 17 baseline proves that the selected
flagless `hifi_playback` stream runs as QTI `DEEP_BUFFER_PLAYBACK` (enum 3) and
then opens PAL stream type 2 (`PAL_STREAM_DEEP_BUFFER`). Android 16 Pudding,
Byron and Myron map the same flagless port to enum 3; their mini debug ELFs do
not contain the Android 17 `HifiPlayback` class.

Enum 3 is therefore the correct route. Reconfiguration safety is a separate
question.

## Do not conflate the two Deep Buffer layers

Xiaomi uses the term Deep Buffer at two independent layers:

- `deep_buffer_out` is an Audio Policy mix-port profile. Both the Android 16
  and Android 17 `HifiSampleRateManager` configure it with `FIRST_LOCK`.
- `hifi_playback` is the USB HIFI policy profile. Both manager generations
  configure it with `LATEST_MAX`, while the QTI/PAL implementation selected
  for the flagless stream is enum 3 / `PAL_STREAM_DEEP_BUFFER`.

Consequently, the `deep_buffer_out` manager policy must not be reused to lock
the HIFI stream. The manager remains the sole rate arbiter for HIFI; the HAL
patch only restores consumption of the manager's `sampling_rate=<rate>`
request on the enum-3 PAL stream.

This is not inferred from names. The Android 16 Nezha and Myron policy-manager
binaries are byte-identical (`SHA-256 3ae2a9bdf1bc8ee54fccd289cabb6b7981e5f5425c0e568078c98cd5203be016`).
Their initialization creates `deep_buffer_out` with strategy value 1, and the
strategy dispatcher maps value 1 to `updateFirstLockStrategy()`. Their
device-output path creates `hifi_playback` with strategy value 0, which maps to
`updateLatestMaxStrategy()`. The distinct Pudding policy binary has the same
calls and dispatcher. Android 17 stores the same split in `kProfileConfigs`.

On the connected Android 17 phone, the live policy dump independently exposes
`hifi_playback` with exactly the seven USB rates advertised by the module:
44.1, 48, 88.2, 96, 176.4, 192 and 384 kHz. This is also direct runtime
confirmation that omitting 352.8 kHz did not convert the route into a fixed or
upsampling profile.

## Android 16 Nezha is the OEM consumer reference

The Android 16 Nezha `MiStreamOutPrimary::setVendorParameters()` contains the
complete Xiaomi `sampling_rate` consumer that is absent from Pudding, Byron,
Pandora, Popsicle and Myron. Its stock sequence is:

1. parse `sampling_rate` and compare it with the current port configuration;
2. publish the requested rate into the stream's `AudioPortConfig` state;
3. for a live usecase-13 PAL handle, take the private configure mutex, invoke
   the concrete Xiaomi standby lifecycle, and release the mutex;
4. allow the following stock configure path to reopen PAL with the new rate.

That block proves the intended Manager-to-HAL contract. It also explains why
patching the policy manager or inventing a second rate-selection state machine
would be wrong: the missing part on the theoretical Android 16 targets is the
HAL consumer, not the manager.

Blindly transplanting the Binder-side Nezha teardown is not safe for enum 3.
The Android 16 base transfer functions on Nezha, Pudding and Myron all reach
`pal_stream_write()` without taking that configure mutex. The Nezha mutex
therefore serializes configure/standby callers but is not a two-sided
close/write protocol for the enum-3 writer. The pointer-layout payload retains
the same published `AudioPortConfig`, concrete standby and stock configure
lifecycle, but assigns teardown to the serialized stream writer before it can
enter `pal_stream_write()`.

## Why a parameter-only enum-3 patch is incomplete on Android 17

Android 17 stock QTI accepts usecases 8 and 13 in
`MiStreamOutPrimary::setVendorParameters("sampling_rate")`. When a PAL handle
is live, it takes the mutex at `MiStreamOutPrimary + 0x978`, invokes standby,
then releases the mutex.

The stock `MiStreamOutPrimary::transfer()` checks the same usecases 8 and 13,
takes the same `+0x978` mutex around the base transfer, and releases it after
`pal_stream_write()`. This is a two-sided protocol:

1. the parameter thread cannot stop/close PAL while a write is in progress;
2. the transfer worker cannot start a write while standby is closing PAL.

The previous module added enum 3 only to the parameter-side allowlist. Live
disassembly of the active module showed that the transfer-side 8/13 guard was
still stock. That left a possible close/write race during a live LATEST_MAX
rate transition.

The corrected Android 17 patch applies the same `{3, 8, 13}` bitset to both
guards and dynamically relocates the transfer TBZ to the stock skip target.
The installer verifies the original lock-entry branch and rejects mixed or
unknown instruction states.

## Why Android 16 uses writer-thread handoff

Android 16 Pudding/Byron and the shifted Myron layout have no equivalent
usecase-3 transfer lock. Their base transfer reads the PAL handle and calls
`pal_stream_write()` without holding the configure mutex. Taking the configure
mutex only in the injected parameter handler therefore does not protect an
already-running write.

`HifiSampleRateManager` also proves that live transitions are real. It tracks
active rates with `FIRST_LOCK` or `LATEST_MAX`; both `startOutput()` and
`stopOutput()` can call `triggerHardwareSampleRateUpdate()`, whose callback
sends `sampling_rate=` to the current output. A second app starting or the
maximum-rate app stopping can therefore update an output whose PAL handle is
already live.

The Android 16 pointer-layout handler therefore splits ownership:

- the Binder parameter hook validates the seven allowed rates and enum 3, then
  publishes only the optional `AudioPortConfig` request;
- a hook at the head of `MiStreamOutPrimary::transfer()` checks requested
  versus cached PAL rate before either normal transfer or `hyperWrite()`;
- the writer thread invokes the concrete stock standby when a handle is live,
  so no other transfer invocation can simultaneously be inside its own PAL
  write for that stream;
- after successful standby it reloads the cache pointer, commits the new rate,
  and resumes stock transfer; the ordinary branch configures immediately,
  while an active `hyperWrite()` pacing branch reopens on its next ordinary
  transfer. A failed standby leaves the cached active rate unchanged.

This is an active adaptive path, not a cold-start fallback. It follows the same
parameter-to-worker ownership model already used by the Dada adaptation while
retaining the exact private offsets and register preservation required by the
Pudding/Byron/Pandora/Popsicle and shifted Myron binaries.
