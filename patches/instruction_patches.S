.section .strategy_restore_patch, "a"
.p2align 2
.global strategy_restore_patch
strategy_restore_patch:
    // Restore the stock per-profile Strategy load.  Deep Buffer is changed to
    // LATEST_MAX in its own static ProfileConfig, leaving VoIP untouched.
    ldr w3, [x24, #8]

.section .profile_init_patch, "a"
.p2align 2
.global profile_init_patch
profile_init_patch:
    // nop the Feature 8 early exit at 0xc3260. This creates Xiaomi's existing
    // deep_buffer_out profile without globally enabling the rest of Feature 8.
    .inst 0xd503201f

.section .effect_gate_patch, "a"
.p2align 2
.global effect_gate_patch
effect_gate_patch:
    // b.hs 0xd55e0 from 0xd55b4: accept NONE(2) and UNKNOWN(3),
    // while retaining Xiaomi's block for DOLBY(0) and MISOUND(1).
    .inst 0x54000162

.section .flinger_sync_patch, "a"
.p2align 2
.global flinger_sync_patch
flinger_sync_patch:
    // b 0x1b0c2c from 0x1b0a84: readOutputParameters_l(true)
    .inst 0x1400006a

.section .hal_deep_buffer_reopen_patch, "a"
.p2align 2
.global hal_deep_buffer_reopen_patch
hal_deep_buffer_reopen_patch:
    // MiStreamOutPrimary::setVendorParameters(sampling_rate): Xiaomi only
    // calls standby() for VOIP(8) and HIFI(13). Preserve both and include
    // DEEP_BUFFER_PLAYBACK(3) using bits 3, 8 and 13 of a local mask.
    mov w9, #0x2108
    lsr w9, w9, w8
    tbz w9, #0, .+0x40
    nop

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
