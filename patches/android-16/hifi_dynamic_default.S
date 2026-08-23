.extern HIFI_DYNAMIC_DEFAULT_RETURN

.section .a16_hifi_dynamic_default, "ax"
.p2align 2
.global a16_hifi_dynamic_default_hook
a16_hifi_dynamic_default_hook:
    ldr     x9, [x22]
    cbz     x9, .Ldone
    ldrb    w10, [x9, #0x30]
    add     x11, x9, #0x31
    ldr     x12, [x9, #0x40]
    tst     w10, #1
    csel    x11, x11, x12, eq
    cbz     x11, .Ldone
    adr     x12, .Lhifi_name
.Lcompare:
    ldrb    w13, [x11], #1
    ldrb    w14, [x12], #1
    cmp     w13, w14
    b.ne    .Ldone
    cbnz    w13, .Lcompare
    mov     w13, #48000
    str     w13, [sp, #0xc0]
.Ldone:
    ldr     d0, [sp, #0xc0]
    b       HIFI_DYNAMIC_DEFAULT_RETURN
.p2align 1
.Lhifi_name:
    .asciz  "hifi_playback"
