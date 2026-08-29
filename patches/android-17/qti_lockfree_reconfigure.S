.arch armv8.1-a+lse

// Android 17 QTI case-3 PAL reconfiguration handoff.
//
// Binder makes the requested rate immediately visible to AudioFlinger while
// the transfer worker owns PAL teardown.  Padding in the existing aligned
// optional-rate slot records the active hardware rate and a dirty bit, so a
// request that returns to the active rate can cancel before standby.

.extern ATOI
.extern A17_PARAMETER_STOCK_RESUME
.extern A17_PARAMETER_SKIP_STANDBY
.extern A17_TRANSFER_LOCK_ENTRY
.extern A17_TRANSFER_SKIP_LOCK
.extern A17_WORKER_STANDBY

.equ A17_USECASE_OFFSET, 0x378
.equ A17_PAL_HANDLE_OFFSET, 0x3c8
.equ A17_PORT_CONFIG_RATE_OFFSET, 0x790
.equ A17_PAL_ATTRIBUTES_SUBOBJECT_OFFSET, 0x298
.equ A17_PAL_ATTRIBUTES_RATE_OFFSET, 0x40
.equ A17_MAILBOX_ACTIVE_SHIFT, 40
.equ A17_MAILBOX_ACTIVE_WIDTH, 20
.equ A17_MAILBOX_DIRTY_BIT, 63

.section .a17_lockfree_cave, "ax"
.p2align 2
.global a17_lockfree_parameter_hook
a17_lockfree_parameter_hook:
    ldrh    w8, [x20, #A17_USECASE_OFFSET]
    cmp     w8, #3
    b.eq    .Lparameter_case3
    sub     x0, x29, #0x50
    b       A17_PARAMETER_STOCK_RESUME

.Lparameter_case3:
    sub     sp, sp, #0x20
    str     x30, [sp]
    sub     x0, x29, #0x50
    bl      ATOI
    str     w0, [sp, #0x8]

    mov     w9, #44100
    mov     w10, #3
.Lparameter_check_441:
    cmp     w0, w9
    b.eq    .Lparameter_valid
    lsl     w9, w9, #1
    subs    w10, w10, #1
    b.ne    .Lparameter_check_441

    mov     w9, #48000
    mov     w10, #4
.Lparameter_check_48:
    cmp     w0, w9
    b.eq    .Lparameter_valid
    lsl     w9, w9, #1
    subs    w10, w10, #1
    b.ne    .Lparameter_check_48
    b       .Lparameter_restore

.Lparameter_valid:
    add     x0, x20, #A17_PAL_ATTRIBUTES_SUBOBJECT_OFFSET
    ldr     x8, [x0]
    ldr     x8, [x8, #0x68]
    blr     x8
    cbz     x0, .Lparameter_restore

    ldr     w9, [sp, #0x8]
    str     w9, [x0, #A17_PAL_ATTRIBUTES_RATE_OFFSET]
    add     x10, x20, #A17_PORT_CONFIG_RATE_OFFSET

.Lparameter_publish_retry:
    ldaxr   x11, [x10]
    ubfx    x12, x11, #A17_MAILBOX_ACTIVE_SHIFT, #A17_MAILBOX_ACTIVE_WIDTH
    cbnz    x12, .Lparameter_active_known
    uxtw    x12, w25

.Lparameter_active_known:
    uxtw    x11, w9
    mov     x13, #1
    orr     x11, x11, x13, lsl #32
    orr     x11, x11, x12, lsl #A17_MAILBOX_ACTIVE_SHIFT
    cmp     w9, w12
    b.eq    .Lparameter_publish
    orr     x11, x11, x13, lsl #A17_MAILBOX_DIRTY_BIT

.Lparameter_publish:
    stlxr   w14, x11, [x10]
    cbnz    w14, .Lparameter_publish_retry

.Lparameter_restore:
    ldr     x30, [sp]
    add     sp, sp, #0x20
    b       A17_PARAMETER_SKIP_STANDBY

.p2align 2
.global a17_lockfree_transfer_hook
a17_lockfree_transfer_hook:
    cmp     w8, #3
    b.eq    .Lworker_case3
    cmp     w8, #13
    b.eq    .Lworker_lock
    cmp     w8, #8
    b.eq    .Lworker_lock
    b       .Lworker_skip

.Lworker_lock:
    b       A17_TRANSFER_LOCK_ENTRY

.Lworker_case3:
    add     x9, x23, #A17_PORT_CONFIG_RATE_OFFSET
    ldar    x10, [x9]
    tbz     x10, #32, .Lworker_skip
    tbz     x10, #A17_MAILBOX_DIRTY_BIT, .Lworker_skip

    sub     sp, sp, #0x20
    str     x30, [sp]

    add     x0, x23, #A17_PAL_ATTRIBUTES_SUBOBJECT_OFFSET
    ldr     x8, [x0]
    ldr     x8, [x8, #0x68]
    blr     x8
    cbz     x0, .Lworker_restore
    str     x0, [sp, #0x10]

    ldr     x8, [x23, #A17_PAL_HANDLE_OFFSET]
    cbz     x8, .Lworker_commit
    mov     x0, x23
    bl      A17_WORKER_STANDBY
    cbnz    w0, .Lworker_restore

.Lworker_commit:
    add     x9, x23, #A17_PORT_CONFIG_RATE_OFFSET

.Lworker_commit_retry:
    ldar    x10, [x9]
    tbz     x10, #32, .Lworker_restore
    tbz     x10, #A17_MAILBOX_DIRTY_BIT, .Lworker_restore

    ldr     x8, [sp, #0x10]
    str     w10, [x8, #A17_PAL_ATTRIBUTES_RATE_OFFSET]
    and     x11, x10, #0xffffffffff
    uxtw    x12, w10
    orr     x11, x11, x12, lsl #A17_MAILBOX_ACTIVE_SHIFT
    mov     x13, x10
    casal   x13, x11, [x9]
    cmp     x13, x10
    b.ne    .Lworker_commit_retry

.Lworker_restore:
    ldr     x30, [sp]
    add     sp, sp, #0x20

.Lworker_skip:
    b       A17_TRANSFER_SKIP_LOCK

.p2align 2
    .space  768 - (. - a17_lockfree_parameter_hook)
