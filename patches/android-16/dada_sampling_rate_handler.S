.extern DADA_STR_PARMS_GET_STR
.extern DADA_ATOI
.extern DADA_RATE_RETURN
.extern DADA_STANDBY
.extern DADA_WORKER_RETURN

// Xiaomi 15 (Dada) keeps its PAL stream attributes in the vendor stream
// object, but its setVendorParameters() runs outside the driver worker.  The
// parameter hook therefore records only the requested AudioPortConfig rate.
.section .a16_dada_rate_parameter, "ax"
.p2align 2
.global a16_dada_rate_parameter
a16_dada_rate_parameter:
    // The displaced stock call has already prepared x1 (its parameter key)
    // and x2 (its result buffer).  Our helper calls may clobber both caller-
    // saved registers, so preserve them in a private aligned frame and restore
    // them before resuming Xiaomi's parser.
    sub     sp, sp, #0x10
    stp     x1, x2, [sp]

    // Only the native hifi/deep-buffer usecase may follow this parameter.
    ldrh    w8, [x27, #0x370]
    cmp     w8, #3
    b.ne    .Lparameter_resume

    mov     x0, x22
    adr     x1, .Lsampling_rate
    sub     x2, x29, #0x50
    mov     w3, #0x40
    bl      DADA_STR_PARMS_GET_STR
    tbnz    w0, #31, .Lparameter_resume

    sub     x0, x29, #0x50
    bl      DADA_ATOI
    mov     w9, w0

    // Accept only rates that the module's Qualcomm USB table actually exposes.
    // The value in w9 is compared and then written back unchanged: this is
    // source-rate following, never multiplication or resampling.
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
    b       .Lparameter_resume

.Lvalid_rate:
    ldr     x10, [x27, #0x4c0]
    cbz     x10, .Lparameter_resume
    ldrb    w11, [x10, #0xc]
    cbz     w11, .Lstore_rate
    ldr     w11, [x10, #0x8]
    cmp     w11, w9
    b.eq    .Lparameter_resume
.Lstore_rate:
    // Publish AudioPortConfig's value and presence discriminator together.
    // The writer hook acquires this aligned eight-byte optional-rate slot.
    add     x10, x10, #0x8
    mov     x11, #0x100000000
    orr     x9, x9, x11
    stlr    x9, [x10]

.Lparameter_resume:
    ldp     x1, x2, [sp]
    add     sp, sp, #0x10
    // Preserve the displaced `mov x0, x22` before Xiaomi's final stock
    // parameter parser with its original key and buffer registers intact.
    mov     x0, x22
    b       DADA_RATE_RETURN

.Lsampling_rate:
    .asciz  "sampling_rate"
.p2align 2
    .space  256 - (. - a16_dada_rate_parameter)

// The stream teardown is intentionally deferred to transfer(), which is the
// driver worker context used by the stock QTI implementation.  This preserves
// Xiaomi's own standby/configure lifecycle and also covers the hyperWrite path.
.section .a16_dada_rate_worker, "ax"
.p2align 2
.global a16_dada_rate_worker
a16_dada_rate_worker:
    // x9 is live across the replaced instruction and is consumed immediately
    // after returning.  Use a private aligned frame instead of borrowing any
    // of transfer()'s local slots.
    sub     sp, sp, #0x10
    str     x9, [sp]
    ldrh    w8, [x23, #0x370]
    cmp     w8, #3
    b.ne    .Lworker_resume

    ldr     x10, [x23, #0x4c0]
    cbz     x10, .Lworker_resume
    add     x10, x10, #0x8
    ldar    x12, [x10]
    tbz     x12, #32, .Lworker_resume

    ldr     x11, [x23, #0x540]
    cbz     x11, .Lworker_resume
    ldr     w8, [x11, #0x40]
    cmp     w8, w12
    b.eq    .Lworker_resume

    str     x10, [sp, #0x8]
    ldr     x10, [x23, #0x3c0]
    cbz     x10, .Lworker_commit
    mov     x0, x23
    bl      DADA_STANDBY
    cbnz    w0, .Lworker_resume
    ldr     x10, [sp, #0x8]
    ldar    x12, [x10]
    ldr     x11, [x23, #0x540]
    cbz     x11, .Lworker_resume

.Lworker_commit:
    // Mark the cached PAL description current.  If standby closed a live PAL
    // handle, the immediately following stock transfer re-enters configure().
    str     w12, [x11, #0x40]

.Lworker_resume:
    ldr     x9, [sp]
    add     sp, sp, #0x10
    // Preserve the displaced `mov w8, wzr`.
    mov     w8, wzr
    b       DADA_WORKER_RETURN

.p2align 2
    .space  128 - (. - a16_dada_rate_worker)
