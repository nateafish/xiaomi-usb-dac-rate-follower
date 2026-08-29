# Android 17 Case-3 PAL worker handoff research

This branch evaluates a worker-owned reconfiguration path for the Xiaomi 17
Ultra Android 17 Qualcomm audio HAL. It is an experimental implementation, not
hardware validation. The exact object offsets and instruction contexts apply
only to the reviewed Nezha SM8850/Canoe HAL layout.

## Stock synchronization model

`MiStreamOutPrimary::setVendorParameters("sampling_rate")` updates the cached
PAL stream attributes, records the optional sample rate at `+0x790/+0x794`, and
for usecases 8 and 13 takes the mutex at `+0x978` before calling the concrete
Xiaomi `standby()` implementation.

`MiStreamOutPrimary::transfer()` takes the same mutex around the base transfer
for usecases 8 and 13. The released module widened both guards to include
usecase 3. That correctly prevents a close/write race, but also puts every
case-3 write through the mutex and performs case-3 PAL teardown on the Binder
parameter thread.

## Experimental ownership change

The experimental patch changes only usecase 3:

1. The Binder hook validates one of the seven advertised rates, updates the
   framework-visible PAL attribute cache, and atomically publishes the target
   plus the last active hardware rate in the aligned slot at `+0x790`.
2. Returning to the active hardware rate clears the pending transition before
   the worker can perform standby; no time-based debounce is used.
3. A changed target causes the transfer worker to invoke concrete Xiaomi
   `MiStreamOutPrimary::standby()` before committing the new cached PAL rate.
4. The worker atomically marks the newest target as active and resumes the
   no-lock stock transfer path. Because standby cleared
   the handle, `StreamOutPrimary::transfer()` reaches stock `configure()` and
   reopens PAL using the committed rate.
5. A failed standby leaves the transition pending, so a later transfer retries
   rather than falsely declaring the new rate active.

Usecases 8 and 13 continue through the original `+0x978` two-sided mutex. No
other usecase is admitted to the worker handoff.

## Verified structural evidence

The device ELF establishes these fields and calls:

| Field | Offset | Evidence |
| --- | ---: | --- |
| usecase | `+0x378` | both stock synchronization guards |
| PAL handle | `+0x3c8` | stock parameter live-handle guard and standby |
| optional target rate | `+0x790` | parameter publisher, configure and position accounting |
| optional presence byte | `+0x794` | parameter publisher, configure and position accounting |
| PAL attributes subobject | `+0x298` | stock virtual getter before rate comparison/update |
| cached PAL rate | getter result `+0x40` | stock comparison and update |
| write mutex | `+0x978` | stock parameter and transfer lock/unlock pairs |

The `+0x794` byte is an optional-value presence discriminator, not a one-shot
dirty flag. The worker therefore compares target and cached rates rather than
treating this byte as pending state.

## Offline validation performed

The build emits a 384-byte relocation template into the zero-filled executable
gap immediately before dynamic symbol `__cfi_check`. Installation resolves the
two function-local hook sites, `atoi`, concrete Xiaomi standby, both stock
transfer continuations and the cave address from the target ELF.

The generated module was applied twice to a Nezha HAL restored to the stock
usecase guards. Both applications were byte-identical. Final disassembly
confirmed:

- Binder case 3 branches to the atomic publisher and skips Binder standby;
- transfer case 3 branches to the worker handoff and bypasses `+0x978`;
- transfer cases 8 and 13 branch back to the original mutex entry;
- the worker calls concrete Xiaomi standby before changing cached PAL rate;
- stock transfer remains responsible for PAL configure and write.

## Remaining hardware questions

Without a connected USB DAC this work cannot establish audible pop behavior,
USB endpoint recovery, actual transition latency, or stability under repeated
44.1/48 kHz clock-family changes. The experiment deliberately does not inject
zero padding or claim to eliminate underruns. Those require captured PAL logs,
AudioFlinger timing and physical DAC observation.
