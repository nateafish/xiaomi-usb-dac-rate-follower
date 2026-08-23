// Historical v0.7.6 USB sender gate, retained only as an exact upgrade/test
// fixture. It is never installed by v0.7.8.

.extern SENDKEY_BODY
.extern SENDKEY_ZERO_PATH

.section .usb_output_gate_v076_cave, "ax"
.p2align 2
.global usb_output_gate_v076
usb_output_gate_v076:
    cbz     w2, SENDKEY_ZERO_PATH
    ldr     x9, [x0, #0xb8]
    cbz     x9, .Ldeny
    cmp     x9, #64
    b.hi    .Ldeny
    ldr     x8, [x0, #0xb0]
    cbz     x8, .Ldeny
.Lfind_output:
    ldr     w10, [x8]
    cmp     w10, w1
    b.eq    .Loutput_found
    add     x8, x8, #0x10
    subs    x9, x9, #1
    b.ne    .Lfind_output
    b       .Ldeny
.Loutput_found:
    ldr     x10, [x8, #0x8]
    cbz     x10, .Ldeny
    ldp     x10, x9, [x10, #0xf0]
    cbz     x9, .Ldeny
    cmp     x9, #16
    b.hi    .Ldeny
    cbz     x10, .Ldeny
.Lcheck_device:
    ldr     x11, [x10], #0x8
    cbz     x11, .Ldeny
    ldr     w12, [x11, #0x148]
    cmp     w12, #0x2000
    b.eq    .Lnext_device
    cmp     w12, #0x4000
    b.eq    .Lnext_device
    mov     w13, #0x04000000
    cmp     w12, w13
    b.ne    .Ldeny
.Lnext_device:
    subs    x9, x9, #1
    b.ne    .Lcheck_device
    b       SENDKEY_BODY
.Ldeny:
    ret
