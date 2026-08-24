# Myron Android 16 audio baseline report

## Identity

- Device: Redmi K90 Pro Max (`myron`, ODM model `25102RKBEC`)
- Android: 16 / API 36
- SoC: Qualcomm SM8850
- Board platform: `canoe`
- Audio HAL: Qualcomm AIDL Audio Core v3
- Vendor/ODM incremental: `OS3.0.308.0.WPMCNXM`

The identity was read from the extracted build properties, VINTF manifest and
audio-module registration rather than inferred from the OTA filename. Runtime
selection is keyed by the exact `myron / SM8850 / canoe / AIDL v3` tuple.

## Core audio objects

| Object | Myron Build ID | SHA-256 relationship |
| --- | --- | --- |
| `libaudiopolicymanagerdefault.so` | `401c42f003e90a9474c4ab2285429ee2` | shared Android 16 policy build |
| `libaudiopolicycomponents.so` | `0cb24b671c461d39d0b004c59e4563f7` | shared Android 16 components build |
| `libaudiopolicymanagerimpl.so` | `334e161add5b3079d48aa3fd7eb3097c` | shared Xiaomi policy implementation |
| `libaudioflingerimpl.so` | `d42b8fb11ae45c2004590af51d85165d` | shared MixerThread build |
| `libdev_usb.so` | `e7bf22d554aff10814bb908f68cacd43` | shared Qualcomm USB build |
| `libaudiocorehal.qti.so` | `5834ea0ef43dcc3e31fb806a7d520c8b` | distinct Myron core HAL (`c98d6778…`) |

The ODM policy declares a dynamic `hifi_playback` mix port routed to the USB
device and headset ports. The Audio Core manifest declares AIDL version 3 for
the default, USB and remote-submix modules. The relevant Qualcomm USB backend
is `libdev_usb.so`; the normal `libar-pal.so` dependency does not make this a
Xiaomi 15/Dada worker-layout target.

## Independent HAL layout

Myron does not reuse the Byron/Pudding private-object layout. The relevant
private members move together by `0x28`:

| Member | Standard Android 16 layout | Myron layout |
| --- | ---: | ---: |
| HIFI usecase tag | `+0x350` | `+0x378` |
| live PAL handle | `+0x3a0` | `+0x3c8` |
| `Platform*` | `+0x758` | `+0x780` |
| `AudioPortConfig*` | `+0x760` | `+0x788` |
| cached PAL attributes | `+0x7e8` | `+0x810` |

The module therefore contains a separately compiled shifted-layout payload and
a separate set of function-local semantic signatures. The installer first
proves every pointer, optional sample-rate field, usecase tag, PAL handle and
linker-owned 384-byte executable gap, plus a transfer entry that dominates both
normal and `hyperWrite()` paths. It aborts before writing if the
normal or shifted layout is absent, ambiguous or partially patched.

The exact Myron wrapper transfer, base transfer, standby and shutdown paths
were inspected. Its internal recursive standby mutex does not cover the case-3
`pal_stream_write()` path, so the parameter thread does not tear down PAL. It
publishes only the requested `AudioPortConfig` value. The separately compiled
shifted worker payload performs standby, reloads the shifted cache pointer,
commits the target rate only on success, and resumes the original transfer /
configure lifecycle on the same writer thread. This preserves active adaptive
switching while removing the close/write race.

Resolved offsets from this OTA are diagnostics only:

- policy hook: `0x51b9c`;
- policy cave: `0xb9520`;
- MixerThread synchronization: `0x154360`;
- Qualcomm USB rate table: `0x7150`;
- HAL rate hook: `0x1e1a34`;
- HAL transfer-worker hook: `0x1e016c`;
- HAL executable cave: `0x13492c`.

Installation re-resolves all locations and branch targets from the live ELF.
No recorded offset, Build ID or whole-file hash is used as a write address or
as the sole compatibility gate.

## Validation and status

The complete patch set passed two consecutive offline applications to the six
stock Myron audio ELF files; the second application was byte-identical. The
validator also corrupted the HAL hook deliberately and confirmed that the
mixed state is rejected instead of overwritten.

`myron-sm8850-canoe-aidl-v3` is installable as a theoretical target only after
the hardware-validation warning and volume-key confirmation. This establishes
structural patch safety, not real-device audio stability, strict Bit Perfect
output or successful rate following. The retained work directory contains only
the six core ELF files; intermediate partition images are removed after the
full regression run.
