# Usecase-3 reconfiguration and transfer concurrency

## Result

The connected Xiaomi 17 Pro Android 17 baseline proves that the selected
flagless `hifi_playback` stream runs as QTI `DEEP_BUFFER_PLAYBACK` (enum 3) and
then opens PAL stream type 2 (`PAL_STREAM_DEEP_BUFFER`). Android 16 Pudding,
Byron and Myron map the same flagless port to enum 3; their mini debug ELFs do
not contain the Android 17 `HifiPlayback` class.

Enum 3 is therefore the correct route. Reconfiguration safety is a separate
question.

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
