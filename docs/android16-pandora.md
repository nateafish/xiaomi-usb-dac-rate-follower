# Pandora Android 16 audio baseline report

## Identity

- Device: Xiaomi 17 Pro (`pandora`)
- Android: 16 / API 36
- SoC: SM8850
- Board platform: `canoe`
- Audio HAL: Qualcomm AIDL Audio Core v3
- Vendor/ODM incremental: `OS3.0.318.0.WBLCNXM`
- System incremental: `16OS3.1.260804.150011551.QCPECN.S`

The complete OTA
`pandora-ota_full-OS3.0.318.0.WBLCNXM-user-16.0-082e9f32b8.zip` was decoded
independently. After validation, only the six core audio ELF files were kept
in the local work tree; intermediate images and complete partition trees were
removed.

## Audio-stack classification

Pandora is the same Android 16 audio family as Popsicle:

- policy manager Build ID `401c42f003e90a9474c4ab2285429ee2`;
- policy components Build ID `0cb24b671c461d39d0b004c59e4563f7`;
- Xiaomi policy implementation Build ID `334e161add5b3079d48aa3fd7eb3097c`;
- AudioFlinger Build ID `b5248898a4bdb0f1663b73e2c1638f75`;
- Qualcomm USB Build ID `e7bf22d554aff10814bb908f68cacd43`;
- QTI core HAL Build ID `c1962c089701a4cf151c86ccc03a480a`.

Its ODM policy declares a flagless, dynamic `hifi_playback` mix port routed
only to `usb_device_out` and `usb_headset`.  The core HAL exports
`DeepBufferPlayback` and `BitPerfectPlayback`, but not `HifiPlayback`, so the
flagless HIFI port follows the Pudding/Popsicle Deep Buffer usecase-3 layout.

Pandora therefore reuses the reviewed Android 16 pointer-layout
`sampling_rate` handler; it does not use the Dada AIDL-v2 worker trampoline or
the Nezha usecase-13 guard.

## Offline validation

The Android 16 patch driver resolved every Pandora site independently:

- native HIFI policy route: `0x51b9c`;
- policy executable cave: `0xb9520`;
- MixerThread HAL synchronization branch: `0x154310`;
- Qualcomm USB rate table: `0x7150`;
- Android 16 HAL rate hook: `0x1cc63c`;
- HAL executable cave: `0x11f1d4`.

These offsets are diagnostics only.  Installation resolves the function-local
signatures, object layouts, imported calls, branch targets and executable gaps
again from the installed files.  Two complete applications were byte-identical.

Firmware hashes remain useful diagnostics but are not equality gates. A later
OTA must still pass every semantic signature, object-layout, branch-target and
executable-gap check. Hardware behavior remains unverified, so installation
requires the existing theoretical-target warning and physical volume-key
confirmation.
