# Target layout

Targets are grouped by Android major version, not by individual firmware.
Each Android directory describes the Qualcomm audio baseline, the relevant
AudioFlinger/HAL generation, and the use cases required by that baseline.

Each Android directory contains shared `usecases/` plus compact `baselines/`
records. A baseline is one exact device / SoC / board tuple, so adding another
device cannot accidentally create a cross-product match with existing lists.
Each exact baseline also has its own validation status. A recorded port that
has passed offline structural validation but not hardware validation remains
installable only after a prominent warning and physical volume-key confirmation.
`target.conf` defines two support tiers:

- `verified`: a recorded Android major version, device and SoC/HAL baseline.
- `compatible`: an unrecorded Qualcomm device whose Android version, HAL
  generation, SONAMEs, semantic strings, unique instruction signatures,
  object-layout anchors and executable caves all match.

A compatible match may be installed with an explicit unverified-device
warning. Firmware incrementals, ELF Build IDs and whole-file hashes are
diagnostic references rather than equality gates. Zero matches, multiple
matches, an unknown layout, or a mixed patch state must abort.

Matching priority is Android SDK, device, SoC model/board platform, HAL
generation and interface version, then the actually loaded Qualcomm library
family. The final write decision is always made by semantic ELF validation.

Shared ELF inspection and AArch64 relocation lives in `tools/elfpatcher`.
Use-case manifests own the semantic signatures and patch intent. Absolute
offsets shown in research notes are diagnostics only and must not be used as
the sole installation decision.

The module ZIP carries one runtime patch driver per Android major version.
Android 17 is installable after all target and semantic checks pass. Android
16 is `theoretical-preview`: its route, dynamic-default, MixerThread, USB table
and Qualcomm HAL use cases passed offline OTA validation. Every baseline that
lacks hardware validation warns and waits for a volume key before applying.

For offline validation, build a host copy of `tools/elfpatcher`, build the
module ZIP, then run:

```sh
bash scripts/validate_offline_target.sh \
  16 /path/to/extracted/audio-targets \
  dist/xiaomi-usb-dac-rate-follower-*.zip \
  /path/to/elfpatcher-host \
  dada-sm8750-sun.conf
```

The optional baseline argument applies its exact library paths and patch
profile. The validator patches copies only and runs the target driver twice.
The second pass must be byte-identical to the first, and Dada validation also
proves that a deliberately mixed pair of HAL hooks is rejected.
