.text
.p2align 2
.global is_app_allowed_hook
.type is_app_allowed_hook, %function
is_app_allowed_hook:
    // x0 = Xiaomi Hifi profile name (unused; this function is Hifi-only)
    // x1 = application package as Android libc++ std::string.
    // Keep the stock prologue and epilogue addresses so the firmware's unwind
    // metadata remains valid after the in-place patch.
    paciasp
    stp     x29, x30, [sp, #-0x40]!
    stp     x24, x23, [sp, #0x10]
    stp     x22, x21, [sp, #0x20]
    stp     x20, x19, [sp, #0x30]
    mov     x29, sp

    ldrb    w8, [x1]
    tbnz    w8, #0, .Llong_string
    lsr     w9, w8, #1
    add     x19, x1, #1
    b       .Lselect_name

.Llong_string:
    ldr     x9, [x1, #8]
    ldr     x19, [x1, #16]

.Lselect_name:
    cmp     x9, #23
    b.eq    .Lapple
    cmp     x9, #22
    b.ne    .Ldeny
    adr     x20, .Lnetease_name
    b       .Lcompare

.Lapple:
    adr     x20, .Lapple_name

.Lcompare:
    ldrb    w8, [x19], #1
    ldrb    w10, [x20], #1
    cmp     w8, w10
    b.ne    .Ldeny
    cbnz    w8, .Lcompare
    mov     w0, #1
    b       .Lepilogue

.Ldeny:
    mov     w0, wzr
    b       .Lepilogue

.Lapple_name:
    .asciz  "com.apple.android.music"
.Lnetease_name:
    .asciz  "com.netease.cloudmusic"

    // Stock epilogue VA: 0xd3c78; function starts at 0xd3bcc.
    .org is_app_allowed_hook + 0xac, 0x1f
.Lepilogue:
    ldp     x20, x19, [sp, #0x30]
    ldp     x22, x21, [sp, #0x20]
    ldp     x24, x23, [sp, #0x10]
    ldp     x29, x30, [sp], #0x40
    autiasp
    ret
.size is_app_allowed_hook, .-is_app_allowed_hook
