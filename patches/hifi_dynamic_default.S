// Exact-firmware AArch64 patch for the dynamic hifi_playback profile.
//
// APM first opens an unspecified dynamic USB output to query its profiles. It
// then calls IOProfile::pickAudioProfile() and reopens the output. On this
// firmware that generic picker chooses PCM32 stereo at 384 kHz. Xiaomi later
// changes the live stream rate, but the AIDL FMQ frame count cannot change.
//
// Hook the instruction immediately after pickAudioProfile(). Preserve the
// chosen channel mask and PCM format, but make only hifi_playback start at
// 48 kHz. QTI then allocates its normal 40 ms / 1920-frame queue, while
// Xiaomi's existing live-rate path handles later 44.1/48/96/... changes.

.extern HIFI_DYNAMIC_DEFAULT_RETURN

.section .hifi_dynamic_default_branch, "ax"
.p2align 2
.global hifi_dynamic_default_branch
hifi_dynamic_default_branch:
    b       hifi_dynamic_default_hook

.section .hifi_dynamic_default_cave, "ax"
.p2align 2
.global hifi_dynamic_default_hook
hifi_dynamic_default_hook:
    // x21 addresses the caller's sp<IOProfile>. IOProfile's name is a libc++
    // std::string at +0x30 (short bytes +0x31, long pointer +0x40).
    ldr     x9, [x21]
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
    str     w13, [sp, #0x1c0]

.Ldone:
    // Replay the displaced instruction and resume the stock function.
    ldr     d0, [sp, #0x1c0]
    b       HIFI_DYNAMIC_DEFAULT_RETURN

.p2align 1
.Lhifi_name:
    .asciz  "hifi_playback"
