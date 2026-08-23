# Target layout

Targets are grouped by Android major version, not by individual firmware.
Each Android directory describes the Qualcomm audio baseline, the relevant
AudioFlinger/HAL generation, and the use cases required by that baseline.

Each Android directory contains shared `usecases/` plus compact `baselines/`
records. A baseline is one exact device / SoC / board tuple, so adding another
device cannot accidentally create a cross-product match with existing lists.
`target.conf` defines two support tiers:

- `verified`: a recorded Android major version, device and SoC/HAL baseline.
- `compatible`: an unrecorded Qualcomm device whose Android version, HAL
  generation, SONAMEs, semantic strings, unique instruction signatures,
  object-layout anchors and executable caves all match.

A compatible match may be installed with an explicit unverified-device
warning. Firmware incrementals and ELF Build IDs are retained as diagnostic
references, not equality gates. A device name, fingerprint, file hash or
fixed offset never makes a compatible target safe by itself. Zero matches,
multiple matches, an unknown layout, or a mixed patch state must abort.

Matching priority is Android SDK, device, SoC model/board platform, HAL
generation and interface version, then the actually loaded Qualcomm library
family. The final write decision is always made by semantic ELF validation.

Shared ELF inspection and AArch64 relocation lives in `tools/elfpatcher`.
Use-case manifests own the semantic signatures and patch intent. Absolute
offsets shown in research notes are diagnostics only and must not be used as
the sole installation decision.

The module ZIP carries one runtime patch driver per Android major version.
Android 17 is installable after all target and semantic checks pass. Android
16 is currently `offline-validated`: its route, dynamic-default, MixerThread,
USB table and Qualcomm HAL use cases can be applied and checked against an
extracted OTA, but the installer deliberately aborts before touching a device.

For offline validation, build a host copy of `tools/elfpatcher`, build the
module ZIP, then run:

```sh
bash scripts/validate_offline_target.sh \
  16 /path/to/extracted/audio-targets \
  dist/xiaomi-usb-dac-rate-follower-*.zip \
  /path/to/elfpatcher-host
```

The validator patches copies only and runs the target driver twice. The
second pass must be byte-identical to the first.
