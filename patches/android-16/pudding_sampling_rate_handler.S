.extern STR_PARMS_GET_STR
.extern ATOI
.extern MUTEX_LOCK
.extern PUDDING_STANDBY
.extern MUTEX_UNLOCK
.extern PUDDING_RATE_RETURN

.section .a16_pudding_sampling_rate_handler, "ax"
.p2align 2
.global a16_pudding_sampling_rate_handler
a16_pudding_sampling_rate_handler:
    // The displaced instruction was `mov x0, x23`.  The stock CBZ immediately
    // before the hook guarantees that x23 is a live str_parms object here.
    mov     x0, x23
    adr     x1, .Lsampling_rate
    sub     x2, x29, #0x50
    mov     w3, #0x40
    bl      STR_PARMS_GET_STR
    tbnz    w0, #31, .Lresume

    sub     x0, x29, #0x50
    bl      ATOI
    mov     w9, w0

    // Accept only the four conventional rates in each 44.1/48 kHz family.
    // Unknown vendor input must not be allowed to reach PAL.
    mov     w10, #44100
    mov     w11, #4
.Lcheck_441_family:
    cmp     w9, w10
    b.eq    .Lvalid_rate
    lsl     w10, w10, #1
    subs    w11, w11, #1
    b.ne    .Lcheck_441_family

    mov     w10, #48000
    mov     w11, #4
.Lcheck_48_family:
    cmp     w9, w10
    b.eq    .Lvalid_rate
    lsl     w10, w10, #1
    subs    w11, w11, #1
    b.ne    .Lcheck_48_family
    b       .Lresume

.Lvalid_rate:
    // Pudding stores both objects by pointer.  Validate both before changing
    // either one so an unexpected layout cannot leave split rate state.
    ldr     x10, [x21, #0x7e8]
    cbz     x10, .Lresume
    ldr     x11, [x21, #0x760]
    cbz     x11, .Lresume
    ldr     w12, [x10, #0x40]
    cmp     w12, w9
    b.eq    .Lresume

    str     w9, [x10, #0x40]
    mov     w12, #1
    strb    w12, [x11, #0xc]
    str     w9, [x11, #0x8]

    // Pudding usecase 3 is its native Deep Buffer equivalent of Nezha's
    // usecase-13 HIFI path.  Other stream types retain their stock lifecycle.
    ldrh    w10, [x21, #0x350]
    cmp     w10, #3
    b.ne    .Lresume
    ldr     x10, [x21, #0x3a0]
    cbz     x10, .Lresume

    // This is the same configure mutex used by Pudding's own configure().
    // standby() does not acquire it; the next write re-enters configure().
    add     x0, x21, #0x790
    bl      MUTEX_LOCK
    mov     x0, x21
    bl      PUDDING_STANDBY
    add     x0, x21, #0x790
    bl      MUTEX_UNLOCK

.Lresume:
    mov     x0, x23
    b       PUDDING_RATE_RETURN

.Lsampling_rate:
    .asciz  "sampling_rate"
.p2align 2
    .space  256 - (. - a16_pudding_sampling_rate_handler)
