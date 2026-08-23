.extern VENDOR_SELECT_OUTPUT_STUB
.extern SELECT_OUTPUT_RETURN

.section .a16_native_hifi_route, "ax"
.p2align 2
.global a16_native_hifi_select_hook
a16_native_hifi_select_hook:
    sub     sp, sp, #0x20
    stp     x2, x3, [sp]
    str     x4, [sp, #0x10]
    bl      VENDOR_SELECT_OUTPUT_STUB
    ldp     x2, x3, [sp]
    ldr     x4, [sp, #0x10]

    cbz     x2, .Ldone
    cbz     x3, .Ldone
    cbz     x4, .Ldone
    ldr     x0, [x2]
    cbz     x0, .Ldone
    adr     x1, .Lapple_utf16
    bl      .Lutf16_equal
    cbnz    w0, .Lallowed
    ldr     x0, [x2]
    adr     x1, .Lnetease_utf16
    bl      .Lutf16_equal
    cbz     w0, .Ldone

.Lallowed:
    ldr     x11, [x3, #0x10]
    cbz     x11, .Ldone
    cmp     x11, #64
    b.hi    .Ldone
    ldr     x12, [x3, #0x8]
    cbz     x12, .Ldone
    ldr     w13, [x4]

.Lfind_selected:
    ldr     w14, [x12]
    cmp     w14, w13
    b.eq    .Lselected
    add     x12, x12, #0x10
    subs    x11, x11, #1
    b.ne    .Lfind_selected
    b       .Ldone

.Lselected:
    ldr     x0, [x12, #0x8]
    cbz     x0, .Ldone
    ldr     x6, [x0, #0x1d0]
    cbz     x6, .Ldone
    bl      .Lis_usb_only
    cbz     w0, .Ldone

    ldr     x11, [x3, #0x10]
    ldr     x12, [x3, #0x8]
.Lfind_hifi:
    ldr     x14, [x12, #0x8]
    cbz     x14, .Lnext
    ldr     x15, [x14, #0x1d0]
    cbz     x15, .Lnext
    ldrb    w6, [x15, #0x30]
    add     x0, x15, #0x31
    ldr     x7, [x15, #0x40]
    tst     w6, #1
    csel    x0, x0, x7, eq
    cbz     x0, .Lnext
    adr     x1, .Lhifi_name
    bl      .Lascii_equal
    cbz     w0, .Lnext
    mov     x0, x14
    bl      .Lis_usb_only
    cbz     w0, .Ldone
    ldr     w16, [x12]
    str     w16, [x4]
    b       .Ldone

.Lnext:
    add     x12, x12, #0x10
    subs    x11, x11, #1
    b.ne    .Lfind_hifi

.Ldone:
    add     sp, sp, #0x20
    b       SELECT_OUTPUT_RETURN

.Lutf16_equal:
    ldrh    w6, [x0], #2
    ldrh    w7, [x1], #2
    cmp     w6, w7
    b.ne    .Lnot_equal
    cbnz    w6, .Lutf16_equal
    mov     w0, #1
    ret

.Lascii_equal:
    ldrb    w2, [x0], #1
    ldrb    w6, [x1], #1
    cmp     w2, w6
    b.ne    .Lnot_equal
    cbnz    w2, .Lascii_equal
    mov     w0, #1
    ret
.Lnot_equal:
    mov     w0, wzr
    ret

.Lis_usb_only:
    cbz     x0, .Lusb_false
    ldr     x6, [x0, #0xf8]
    cbz     x6, .Lusb_false
    cmp     x6, #16
    b.hi    .Lusb_false
    ldr     x7, [x0, #0xf0]
    cbz     x7, .Lusb_false
.Lusb_loop:
    ldr     x8, [x7], #8
    cbz     x8, .Lusb_false
    ldr     w9, [x8, #0x148]
    cmp     w9, #0x2000
    b.eq    .Lusb_next
    cmp     w9, #0x4000
    b.eq    .Lusb_next
    mov     w10, #0x04000000
    cmp     w9, w10
    b.ne    .Lusb_false
.Lusb_next:
    subs    x6, x6, #1
    b.ne    .Lusb_loop
    mov     w0, #1
    ret
.Lusb_false:
    mov     w0, wzr
    ret

.p2align 1
.Lapple_utf16:
    .hword  'c','o','m','.','a','p','p','l','e','.','a','n','d','r','o','i','d','.','m','u','s','i','c',0
.Lnetease_utf16:
    .hword  'c','o','m','.','n','e','t','e','a','s','e','.','c','l','o','u','d','m','u','s','i','c',0
.Lhifi_name:
    .asciz  "hifi_playback"
.p2align 2
    .space  640 - (. - a16_native_hifi_select_hook)
