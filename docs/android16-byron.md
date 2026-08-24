# Byron Android 16 audio baseline report

## Identity

- Device: Xiaomi 17 Max (`byron`, ODM model `2605EPN8EC`)
- Android: 16 / API 36
- Vendor target: `mivendor_sm8850`
- Board platform: `canoe`
- Audio HAL: Qualcomm AIDL Audio Core v3
- System/vendor/ODM incremental: `OS3.0.308.0.WAFCNXM`

The identity was read from the extracted build properties and Audio Core VINTF
manifest, not inferred from the OTA filename. Runtime selection remains keyed
by the exact `byron / SM8850 / canoe / AIDL v3` tuple.

## Core audio objects

| Object | Byron Build ID | Relationship |
| --- | --- | --- |
| `libaudiopolicymanagerdefault.so` | `401c42f003e90a9474c4ab2285429ee2` | shared Android 16 policy build |
| `libaudiopolicycomponents.so` | `0cb24b671c461d39d0b004c59e4563f7` | shared Android 16 components build |
| `libaudiopolicymanagerimpl.so` | `334e161add5b3079d48aa3fd7eb3097c` | shared Xiaomi policy implementation |
| `libaudioflingerimpl.so` | `d42b8fb11ae45c2004590af51d85165d` | shared MixerThread build |
| `libdev_usb.so` | `e7bf22d554aff10814bb908f68cacd43` | shared Qualcomm USB build |
| `libaudiocorehal.qti.so` | `8e108e51c3e4ce824f17b99e46fc65af` | distinct Byron core HAL |

The ODM policy declares a dynamic, flagless `hifi_playback` mix port routed to
`usb_device_out` and `usb_headset`. The Audio Core manifest declares version 3
for the default, USB and remote-submix modules.

## HAL classification and safety checks

The distinct core HAL uniquely resolves the shared Android 16 pointer layout:

- `AudioPortConfig*` and cached PAL-attribute pointers;
- configure mutex and sample-rate value/discriminator fields;
- Deep Buffer usecase tag and live PAL-handle fields;
- concrete `MiStreamOutPrimary::standby()` symbol; and
- the linker-owned 256-byte executable gap and its owner call.

The concrete standby wrapper, base standby, shutdown path and platform-device
helper were disassembled for this exact Build ID. They do not acquire the
configure mutex used by the injected handler, and the wrapper returns its
integer status in `w0`. The transactional handler can therefore close a live
old-rate stream, abandon a failed standby without publishing new state, and
commit only the seven supported module rates.

Resolved Byron offsets are diagnostics only:

- policy hook: `0x51b9c`;
- policy cave: `0xb9520`;
- MixerThread synchronization: `0x154360`;
- Qualcomm USB rate table: `0x7150`;
- HAL rate hook: `0x1cc638`;
- HAL executable cave: `0x11f1d4`.

Installation re-resolves every signature, symbol, object-layout anchor, branch
target and executable gap from the installed files. No offset or whole-file
hash above is used as an installation gate.

## Validation and status

The complete Android 16 patch set passed two consecutive offline applications;
the second was byte-identical to the first. A deliberately corrupted HAL hook
was rejected as an unknown/mixed state. The retained local work directory
contains only the six core audio ELF files; intermediate partition images and
configuration evidence were removed after recording the result.

`byron-sm8850-canoe-aidl-v3` is therefore installable as a theoretical target
after the warning and physical volume-key confirmation. Audio stability and
source-rate following still require hardware validation.
