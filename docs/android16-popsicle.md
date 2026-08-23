# Popsicle Android 16 audio baseline report

## Identity

- Device: Xiaomi 17 Pro Max (`popsicle`, ODM model `2509FPN0BC`)
- Android: 16 / API 36
- SoC vendor target: `mivendor_sm8850`
- Board platform: `canoe`
- Audio HAL: Qualcomm AIDL Audio Core v3
- Vendor/ODM incremental: `OS3.0.318.0.WPBCNXM`
- System incremental: `16OS3.1.260804.151813486.QCPECN.S`

The partition properties, not the OTA filename alone, are the recorded
identity. The runtime baseline remains keyed by Android major, device, SM8850,
canoe, AIDL generation and the semantic ELF checks.

## Core audio objects

| Object | Popsicle Build ID | Relationship |
| --- | --- | --- |
| `libaudiopolicymanagerdefault.so` | `401c42f003e90a9474c4ab2285429ee2` | byte-identical to Nezha Android 16 |
| `libaudiopolicycomponents.so` | `0cb24b671c461d39d0b004c59e4563f7` | byte-identical to Nezha Android 16 |
| `libaudiopolicymanagerimpl.so` | `334e161add5b3079d48aa3fd7eb3097c` | byte-identical to Nezha Android 16 |
| `libaudioflingerimpl.so` | `b5248898a4bdb0f1663b73e2c1638f75` | Popsicle build; shared MixerThread signature |
| `libdev_usb.so` | `e7bf22d554aff10814bb908f68cacd43` | byte-identical to Pudding Android 16 |
| `libaudiocorehal.qti.so` | `c1962c089701a4cf151c86ccc03a480a` | distinct build; Pudding-family layout |

`audiohalservice.qti` is byte-identical to Pudding. The default core HAL is
byte-identical across Nezha, Pudding and Popsicle.

## Adaptation classification

Popsicle is a hybrid baseline rather than a whole-file clone of either device:

- its AOSP/Xiaomi policy libraries use the Nezha Android 16 build;
- its Qualcomm USB library and audio service use the Pudding build;
- its AudioFlinger library is distinct but retains the same semantic
  MixerThread rate-synchronization path; and
- its Qualcomm core HAL is distinct, but all Pudding pointer-layout anchors
  resolve uniquely.

The ODM policy declares a flagless dynamic `hifi_playback` mix port routed only
to USB devices. The HAL has `DeepBufferPlayback` and `BitPerfectPlayback`, but
no `HifiPlayback` helper. As in Pudding, QTI maps the flagless port to Deep
Buffer usecase 3. Therefore Popsicle uses the Pudding-specific
`sampling_rate` handler rather than the Nezha usecase-13 guard.

Resolved Popsicle HAL locations are diagnostics only:

- rate hook context: `0x1cc630`
- Platform/AudioPortConfig pointer layout: `0x1cb828`
- cached PAL attributes: `0x1cb898`
- configure mutex and sample-rate consumer: `0x1aec24` / `0x1af48c`
- usecase tag and PAL handle: `0x1caa70` / `0x1abe40`
- linker-owned executable-gap anchor: `0x11f1b0`

No offset above is an installation gate. The module resolves the function,
object layout, PLT targets, branch destinations and executable gap again from
the actual file.

## Validation and status

The Android 16 driver successfully applied the native HIFI route, dynamic
default, MixerThread synchronization, Qualcomm USB 44.1 kHz table fix and
Pudding-family HAL rate handler to copied Popsicle OTA files. A second complete
application was byte-identical to the first.

`popsicle-sm8850-canoe-aidl-v3` is recorded as theoretically validated from
the offline OTA. Installation is allowed after a warning and volume-key
confirmation that hardware validation is still missing. No firmware image or
extracted binary is stored in Git.
