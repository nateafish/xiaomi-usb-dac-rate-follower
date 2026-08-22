.section .latest_max_patch, "a"
.p2align 2
.global latest_max_patch
latest_max_patch:
    // mov w3, wzr: ProfileManager::initialize(..., LATEST_MAX = 0)
    .inst 0x2a1f03e3

.section .effect_gate_patch, "a"
.p2align 2
.global effect_gate_patch
effect_gate_patch:
    // b 0xd55e0 from 0xd55b4: continue to Xiaomi's existing app allow check
    // even when a global Dolby/MiSound state is active.
    .inst 0x1400000b

.section .flinger_sync_patch, "a"
.p2align 2
.global flinger_sync_patch
flinger_sync_patch:
    // b 0x1b0c2c from 0x1b0a84: readOutputParameters_l(true)
    .inst 0x1400006a

.section .usb_441_patch, "a"
.p2align 2
.global usb_441_patch
usb_441_patch:
    // 44100, little-endian uint32_t: replace 352800 at libdev_usb+0x7160.
    .long 44100

.section .usb_3528_patch, "a"
.p2align 2
.global usb_3528_patch
usb_3528_patch:
    // 352800: replace the later 44100 priority entry at libdev_usb+0x717c.
    .long 352800
