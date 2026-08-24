// Exact-firmware AArch64 transport and idle-rate arbitration for
// Xiaomi/nezha OS4.0.0.15.
//
// HifiSampleRateManager's callback receives an audio_io_handle_t, but Xiaomi's
// stock sendkeySamplingRateToAHal() forwards sampling_rate to that output
// without checking its route or lifecycle state. The gate permits only
// USB-routed writes and interprets rate 1 as an internal final-stop handoff
// marker. The marker becomes 48 kHz only when another USB output is active;
// otherwise it is suppressed. Real source rates pass through unchanged.

.extern SENDKEY_BODY
.extern SENDKEY_ZERO_PATH
.extern IS_USB_ONLY_OUTPUT
.extern OUTPUT_IS_ACTIVE

.section .usb_output_gate_branch, "ax"
.p2align 2
.global usb_output_gate_branch
usb_output_gate_branch:
    b       usb_output_gate

// Keep the 140-byte cave as a deterministic trampoline so the existing cave
// layout and the following independently validated payload remain stable.
.section .usb_output_gate_cave, "ax"
.p2align 2
.global usb_output_gate
usb_output_gate:
    b       usb_output_arbitration
    .space  136

.section .usb_output_arbitration_cave, "ax"
.p2align 2
.global usb_output_arbitration

// Entry at AudioPolicyManager::sendkeySamplingRateToAHal + 4:
//   x0 = AudioPolicyManager*, w1 = output handle, w2 = requested rate
// This hook runs before the stock function prologue, so it saves its own link
// register and every callee-saved register it uses.
usb_output_arbitration:
    stp     x29, x30, [sp, #-0x50]!
    stp     x19, x20, [sp, #0x10]
    stp     x21, x22, [sp, #0x20]
    stp     x23, x24, [sp, #0x30]
    str     x25, [sp, #0x40]
    mov     x29, sp
    mov     x19, x0
    mov     w20, w1
    mov     w21, w2
    cbz     w21, .Lzero

    // mOutputs is a DefaultKeyedVector<audio_io_handle_t,
    // sp<SwAudioOutputDescriptor>> at AudioPolicyManager + 0xa8.
    ldr     x22, [x19, #0xb8]
    cbz     x22, .Ldeny
    cmp     x22, #64
    b.hi    .Ldeny
    ldr     x23, [x19, #0xb0]
    cbz     x23, .Ldeny

.Lfind_target:
    ldr     w8, [x23]
    cmp     w8, w20
    b.eq    .Ltarget_found
    add     x23, x23, #0x10
    subs    x22, x22, #1
    b.ne    .Lfind_target
    b       .Ldeny

.Ltarget_found:
    ldr     x25, [x23, #0x8]
    cbz     x25, .Ldeny
    mov     x0, x25
    bl      IS_USB_ONLY_OUTPUT
    cbz     w0, .Ldeny

    // Every real source rate passes through unchanged. Rate 1 is generated
    // only by the final-stop HIFI hook and must never reach the HAL.
    cmp     w21, #1
    b.ne    .Lallow

    // Restore 48 kHz only when another USB-routed output is already active and
    // therefore owns the shared USB backend. This covers Deep Buffer takeover
    // without changing an idle DAC just before HIFI enters standby.
    ldr     x22, [x19, #0xb8]
    ldr     x23, [x19, #0xb0]
.Lscan_other:
    ldr     x24, [x23, #0x8]
    cbz     x24, .Lnext_other
    cmp     x24, x25
    b.eq    .Lnext_other
    mov     x0, x24
    mov     w1, wzr
    bl      OUTPUT_IS_ACTIVE
    cbz     w0, .Lnext_other
    mov     x0, x24
    bl      IS_USB_ONLY_OUTPUT
    cbz     w0, .Lnext_other
    mov     w21, #48000
    b       .Lallow
.Lnext_other:
    add     x23, x23, #0x10
    subs    x22, x22, #1
    b.ne    .Lscan_other
    b       .Ldeny

.Lallow:
    mov     x0, x19
    mov     w1, w20
    mov     w2, w21
    ldr     x25, [sp, #0x40]
    ldp     x23, x24, [sp, #0x30]
    ldp     x21, x22, [sp, #0x20]
    ldp     x19, x20, [sp, #0x10]
    ldp     x29, x30, [sp], #0x50
    b       SENDKEY_BODY

.Lzero:
    ldr     x25, [sp, #0x40]
    ldp     x23, x24, [sp, #0x30]
    ldp     x21, x22, [sp, #0x20]
    ldp     x19, x20, [sp, #0x10]
    ldp     x29, x30, [sp], #0x50
    b       SENDKEY_ZERO_PATH

.Ldeny:
    ldr     x25, [sp, #0x40]
    ldp     x23, x24, [sp, #0x30]
    ldp     x21, x22, [sp, #0x20]
    ldp     x19, x20, [sp, #0x10]
    ldp     x29, x30, [sp], #0x50
    ret
    .space  12
