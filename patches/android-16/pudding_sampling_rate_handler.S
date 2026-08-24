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

    // Accept only the seven rates advertised by this module.  352.8 kHz is
    // intentionally omitted so PAL's seven-entry array retains 44.1 kHz.
    mov     w10, #44100
    mov     w11, #3
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
    // Only the native HIFI usecase participates in rate following.  Reject
    // other streams before reading or changing any private object state.
    ldrh    w10, [x21, #0x350]
    cmp     w10, #3
    b.ne    .Lresume

    // This Android 16 layout stores both objects by pointer.  Validate both
    // before changing either one so an unexpected layout cannot leave split
    // rate state.
    ldr     x10, [x21, #0x7e8]
    cbz     x10, .Lresume
    ldr     x11, [x21, #0x760]
    cbz     x11, .Lresume
    ldr     w12, [x10, #0x40]
    cmp     w12, w9
    b.eq    .Lresume

    // If a PAL stream is live, close the old-rate stream first.  Keep the
    // requested rate and standby result in our own aligned stack frame because
    // all three calls may clobber caller-saved registers.
    ldr     x10, [x21, #0x3a0]
    cbz     x10, .Lcommit

    // This is the same configure mutex used by the stock configure() method.
    // The inspected standby wrapper does not acquire it itself.
    sub     sp, sp, #16
    str     w9, [sp]
    add     x0, x21, #0x790
    bl      MUTEX_LOCK
    mov     x0, x21
    bl      PUDDING_STANDBY
    str     w0, [sp, #4]
    add     x0, x21, #0x790
    bl      MUTEX_UNLOCK
    ldr     w12, [sp, #4]
    ldr     w9, [sp]
    add     sp, sp, #16
    cbnz    w12, .Lresume

    // standby() may update private state, so re-load and re-check both
    // pointers before committing the new rate.
    ldr     x10, [x21, #0x7e8]
    cbz     x10, .Lresume
    ldr     x11, [x21, #0x760]
    cbz     x11, .Lresume

.Lcommit:
    // Publish value before its presence discriminator, then update the cache.
    // At this point no live old-rate PAL stream remains.
    str     w9, [x11, #0x8]
    mov     w12, #1
    strb    w12, [x11, #0xc]
    str     w9, [x10, #0x40]

.Lresume:
    mov     x0, x23
    b       PUDDING_RATE_RETURN

.Lsampling_rate:
    .asciz  "sampling_rate"
.p2align 2
    .space  256 - (. - a16_pudding_sampling_rate_handler)
