// Exact-firmware AArch64 hook for Xiaomi/nezha OS4.0.0.15.XPACNXM.
//
// Xiaomi keeps independent ProfileManager counters for hifi_playback and
// deep_buffer_out, but both logical outputs ultimately program one physical
// USB backend.  This hook replaces the final per-profile "changed" test with
// a lock-local arbitration decision.  It performs no polling and owns no new
// persistent state: the vendor counters remain the single source of truth.

.extern PROFILE_LOOKUP
.extern ARBITER_CALL_PATH
.extern ARBITER_SKIP_PATH

.section .shared_arbiter_branch, "ax"
.p2align 2
.global shared_arbiter_branch
shared_arbiter_branch:
    b       shared_usb_arbiter

.section .shared_arbiter_cave, "ax"
.p2align 2
.global shared_usb_arbiter

// Entered from HifiSampleRateManager::handlePlaybackEvent at VA 0xd57bc.
// The manager's shared mutex is still held.  Important live registers:
//   x19 = HifiSampleRateManager*, x24 = event profile
//   w20 = event output handle, w22 = event rate, w23 = starting
//   w25 = event profile changed, w26 = event profile's candidate rate
//   x3  = package/profile string used by the stock log path
shared_usb_arbiter:
    sub     sp, sp, #0x40
    stp     x29, x30, [sp, #0x00]
    str     x3, [sp, #0x10]

    // Resolve both existing Profile objects while the caller holds the map
    // lock.  PROFILE_LOOKUP returns a borrowed pointer or null.
    add     x0, x19, #0x90
    adr     x1, .Lhifi_name
    bl      PROFILE_LOOKUP
    str     x0, [sp, #0x18]
    cbz     x0, .Lfallback

    add     x0, x19, #0x90
    adr     x1, .Ldeep_name
    bl      PROFILE_LOOKUP
    str     x0, [sp, #0x20]
    cbz     x0, .Lfallback

    // Return (total active clients, maximum active rate) for each profile.
    ldr     x0, [sp, #0x18]
    bl      .Lsummarize_profile
    stp     w0, w1, [sp, #0x28]
    ldr     x0, [sp, #0x20]
    bl      .Lsummarize_profile
    stp     w0, w1, [sp, #0x30]

    ldp     w8, w9, [sp, #0x28]    // HIFI total, max
    ldp     w10, w11, [sp, #0x30]  // Deep total, max
    cbz     w8, .Lno_hifi
    cbz     w10, .Lhifi_controls

    // Both profiles are active.  Deep Buffer temporarily controls the shared
    // backend; stopping it restores the still-active HIFI rate below.
    mov     w26, w11
    ldr     x12, [sp, #0x20]
    ldr     w13, [x12, #0x38]
    cbz     w13, .Lkeep_event_output_deep
    mov     w20, w13
.Lkeep_event_output_deep:
    cmp     x24, x12
    b.ne    .Lhifi_event_while_deep
    // A first 48 kHz Deep start may not change Deep's own default, but it does
    // change a previously active 44.1/96 kHz HIFI backend. Conversely, a first
    // Deep rate equal to HIFI needs no redundant HAL write even if Deep's own
    // local default changed.
    tbz     w23, #0, .Ldeep_regular_change
    cmp     w10, #1
    b.ne    .Ldeep_regular_change
    cmp     w11, w9
    b.ne    .Lcall
    b       .Lskip
.Ldeep_regular_change:
    tbnz    w25, #0, .Lcall
    b       .Lskip

.Lhifi_event_while_deep:
    // HIFI becoming active enables arbitration.  If Deep was already active,
    // program its current rate once unless the stock idle backend is 48 kHz.
    tbz     w23, #0, .Lskip
    cmp     w8, #1
    b.ne    .Lskip
    mov     w14, #48000
    cmp     w11, w14
    b.ne    .Lcall
    b       .Lskip

.Lhifi_controls:
    mov     w26, w9
    ldr     x12, [sp, #0x18]
    ldr     w13, [x12, #0x38]
    cbz     w13, .Lkeep_event_output_hifi
    mov     w20, w13
.Lkeep_event_output_hifi:
    cmp     x24, x12
    b.eq    .Lcontroller_changed
    // This can only be the final Deep stop.  Restore HIFI if its maximum is
    // different from the rate that owned the backend immediately beforehand.
    tbnz    w23, #0, .Lskip
    cmp     w9, w22
    b.ne    .Lcall
    b       .Lskip

.Lcontroller_changed:
    tbnz    w25, #0, .Lcall
    b       .Lskip

.Lno_hifi:
    // Without selected-package HIFI activity, preserve Android's normal
    // 48 kHz policy.  Deep-only source-rate changes must not make the global
    // USB backend adaptive.
    ldr     x12, [sp, #0x18]
    cmp     x24, x12
    b.ne    .Lskip
    tbnz    w23, #0, .Lskip
    mov     w26, #48000
    cbz     w10, .Llast_hifi_without_deep
    ldr     x12, [sp, #0x20]
    ldr     w13, [x12, #0x38]
    cbz     w13, .Lcompare_deep_to_idle
    mov     w20, w13
.Lcompare_deep_to_idle:
    cmp     w11, w26
    b.ne    .Lcall
    b       .Lskip
.Llast_hifi_without_deep:
    cmp     w22, w26
    b.ne    .Lcall
    b       .Lskip

.Lfallback:
    // Missing profiles indicate an unexpected firmware/layout state.  Fall
    // back to Xiaomi's original per-profile decision instead of guessing.
    tbnz    w25, #0, .Lcall

.Lskip:
    ldr     x3, [sp, #0x10]
    ldp     x29, x30, [sp, #0x00]
    add     sp, sp, #0x40
    b       ARBITER_SKIP_PATH

.Lcall:
    ldr     x3, [sp, #0x10]
    ldp     x29, x30, [sp, #0x00]
    add     sp, sp, #0x40
    b       ARBITER_CALL_PATH

// x0 = Profile*.  Return w0 = total positive references, w1 = maximum rate.
.Lsummarize_profile:
    mov     w1, wzr
    mov     w2, wzr
    ldr     x8, [x0, #0x78]
.Lsummary_loop:
    cbz     x8, .Lsummary_done
    ldr     w9, [x8, #0x14]
    cbz     w9, .Lsummary_next
    add     w2, w2, w9
    ldr     w10, [x8, #0x10]
    cmp     w10, w1
    csel    w1, w10, w1, hi
.Lsummary_next:
    ldr     x8, [x8]
    b       .Lsummary_loop
.Lsummary_done:
    mov     w0, w2
    ret

// libc++ short-string layout: size*2 byte followed by inline characters.
.p2align 3
.Lhifi_name:
    .byte   26
    .ascii  "hifi_playback"
    .zero   10
.Ldeep_name:
    .byte   30
    .ascii  "deep_buffer_out"
    .zero   8
