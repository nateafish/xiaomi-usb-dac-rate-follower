.extern STR_PARMS_GET_STR
.extern ATOI
.extern PUDDING_RATE_RETURN
.extern PUDDING_WORKER_STANDBY
.extern PUDDING_WORKER_RETURN

#ifndef A16_POINTER_LAYOUT_SHIFT
#define A16_POINTER_LAYOUT_SHIFT 0
#endif

.equ A16_POINTER_USECASE_OFFSET, 0x350 + A16_POINTER_LAYOUT_SHIFT
.equ A16_POINTER_CONFIG_OFFSET, 0x760 + A16_POINTER_LAYOUT_SHIFT
.equ A16_POINTER_CACHED_ATTR_OFFSET, 0x7e8 + A16_POINTER_LAYOUT_SHIFT
.equ A16_POINTER_PAL_HANDLE_OFFSET, 0x3a0 + A16_POINTER_LAYOUT_SHIFT

.section .a16_pudding_sampling_rate_handler, "ax"
.p2align 2
.global a16_pudding_sampling_rate_handler
a16_pudding_sampling_rate_handler:
    // HifiSampleRateManager remains the only rate arbiter.  This hook restores
    // the HAL consumer that exists in the Android 16 Nezha reference; it does
    // not reuse the separate FIRST_LOCK deep_buffer_out policy profile.
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
    ldrh    w10, [x21, #A16_POINTER_USECASE_OFFSET]
    cmp     w10, #3
    b.ne    .Lresume

    // The Binder parameter thread publishes only the requested
    // AudioPortConfig value.  It must never close PAL or modify the active PAL
    // attribute cache while transfer() can be inside pal_stream_write().
    ldr     x11, [x21, #A16_POINTER_CONFIG_OFFSET]
    cbz     x11, .Lresume
    ldrb    w12, [x11, #0xc]
    cbz     w12, .Lpublish
    ldr     w12, [x11, #0x8]
    cmp     w12, w9
    b.eq    .Lresume

.Lpublish:
    // Publish the value before its presence discriminator.  The transfer
    // worker below consumes this request and owns the complete standby /
    // cached-attribute / configure handoff.
    str     w9, [x11, #0x8]
    mov     w12, #1
    strb    w12, [x11, #0xc]

.Lresume:
    mov     x0, x23
    b       PUDDING_RATE_RETURN

.Lsampling_rate:
    .asciz  "sampling_rate"
.p2align 2
    .space  256 - (. - a16_pudding_sampling_rate_handler)

// The Android 16 Nezha reference handles this request on the Binder thread for
// usecase 13, but its configure mutex is not held by pal_stream_write().
// Android 16 has no corresponding two-sided mutex for usecase 3.  Enum-3
// reconfiguration therefore runs at the head of Xiaomi's transfer() worker,
// before either the ordinary QTI transfer or hyperWrite branch.  The Binder
// thread only records the manager's intent; the writer thread performs the
// same concrete Xiaomi standby and makes the PAL attribute cache current
// before stock code continues.
.section .a16_pointer_rate_worker, "ax"
.p2align 2
.global a16_pointer_rate_worker
a16_pointer_rate_worker:
    // The displaced instruction reads [x9], and the older pointer layout also
    // leaves x3/x4 live until the final base transfer call.  Preserve all
    // three across the standby call in a private aligned frame.
    sub     sp, sp, #0x20
    stp     x9, x3, [sp]
    str     x4, [sp, #0x10]

#if A16_POINTER_LAYOUT_SHIFT == 0
    ldrh    w8, [x21, #A16_POINTER_USECASE_OFFSET]
#else
    ldrh    w8, [x23, #A16_POINTER_USECASE_OFFSET]
#endif
    cmp     w8, #3
    b.ne    .Lworker_resume

#if A16_POINTER_LAYOUT_SHIFT == 0
    ldr     x10, [x21, #A16_POINTER_CONFIG_OFFSET]
#else
    ldr     x10, [x23, #A16_POINTER_CONFIG_OFFSET]
#endif
    cbz     x10, .Lworker_resume
    ldrb    w8, [x10, #0xc]
    tbz     w8, #0, .Lworker_resume
    ldr     w12, [x10, #0x8]

#if A16_POINTER_LAYOUT_SHIFT == 0
    ldr     x11, [x21, #A16_POINTER_CACHED_ATTR_OFFSET]
#else
    ldr     x11, [x23, #A16_POINTER_CACHED_ATTR_OFFSET]
#endif
    cbz     x11, .Lworker_resume
    ldr     w8, [x11, #0x40]
    cmp     w8, w12
    b.eq    .Lworker_resume

#if A16_POINTER_LAYOUT_SHIFT == 0
    ldr     x10, [x21, #A16_POINTER_PAL_HANDLE_OFFSET]
#else
    ldr     x10, [x23, #A16_POINTER_PAL_HANDLE_OFFSET]
#endif
    cbz     x10, .Lworker_commit
    str     w12, [sp, #0x18]
#if A16_POINTER_LAYOUT_SHIFT == 0
    mov     x0, x21
#else
    mov     x0, x23
#endif
    bl      PUDDING_WORKER_STANDBY
    cbnz    w0, .Lworker_resume
    ldr     w12, [sp, #0x18]
#if A16_POINTER_LAYOUT_SHIFT == 0
    ldr     x11, [x21, #A16_POINTER_CACHED_ATTR_OFFSET]
#else
    ldr     x11, [x23, #A16_POINTER_CACHED_ATTR_OFFSET]
#endif
    cbz     x11, .Lworker_resume

.Lworker_commit:
    str     w12, [x11, #0x40]

.Lworker_resume:
    ldp     x9, x3, [sp]
    ldr     x4, [sp, #0x10]
    add     sp, sp, #0x20
    // Preserve the displaced `ldrb w8, [x9]` before Xiaomi's stock gates.
    ldrb    w8, [x9]
    b       PUDDING_WORKER_RETURN

.p2align 2
    .space  128 - (. - a16_pointer_rate_worker)
