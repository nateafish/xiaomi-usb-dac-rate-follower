// Exact-firmware AArch64 hook for Xiaomi/nezha OS4.0.0.15.XPACNXM.
//
// This deliberately uses AUDIO_MIXER_BEHAVIOR_DEFAULT.  Preferred Mixer is
// only the routing mechanism which selects the dynamic USB hifi_playback
// IOProfile.  Xiaomi's existing HifiSampleRateManager remains responsible for
// following the active tracks' sample rates.

.extern HIFI_INIT_RETURN
.extern GET_OUTPUT_HOOK_RETURN
.extern GET_PREFERRED_INFO
.extern SET_PREFERRED_ATTRIBUTES
.extern REFBASE_DEC_STRONG_PLT

.section .hifi_config_branch, "ax"
.p2align 2
.global hifi_config_branch
hifi_config_branch:
    b       hifi_config_default_hook

.section .preferred_hifi_branch, "ax"
.p2align 2
.global preferred_hifi_branch
preferred_hifi_branch:
    b       preferred_hifi_hook

.section .preferred_hifi_cave, "ax"
.p2align 2
.global hifi_config_default_hook
.global preferred_hifi_hook

// Replaces the instruction at VA 0x38800 after the stock initializer has
// emitted the hifi_playback ProfileConfig with Strategy=LATEST_MAX and a zero
// default rate.  createHifiProfile rejects that zero at VA 0xd4114.
hifi_config_default_hook:
    // The first temporary ProfileConfig begins at sp+0x50.  Change only
    // deep_buffer_out from FIRST_LOCK (1) to LATEST_MAX (0), instead of
    // overriding the strategy argument for every profile (including VoIP).
    str     wzr, [sp, #0x58]
    mov     w9, #48000
    str     w9, [sp, #0xb4]
    mov     w9, #0x04000000
    b       HIFI_INIT_RETURN

// Entered from getOutputForAttrInt at VA 0x5575c.
// Live firmware registers at that point:
//   x26 = AudioPolicyManager*, x27 = resolved audio_attributes_t*
//   w23 = selected device port id, w24 = uid, w2 = product strategy
// The stock instruction replaced by the branch is replayed before returning.
preferred_hifi_hook:
    sub     sp, sp, #0x50
    stp     x29, x30, [sp, #0x00]
    stp     x20, x19, [sp, #0x10]
    str     x2, [sp, #0x20]

    // Media usage only.
    ldr     w8, [x27, #4]
    cmp     w8, #1
    b.ne    .Lreturn_to_policy

    // x19 is the selected DeviceDescriptor.  Check its stable device type,
    // never the framework port id (which is assigned dynamically per attach).
    ldr     w8, [x19, #0x148]
    cmp     w8, #0x2000             // AUDIO_DEVICE_OUT_USB_ACCESSORY
    b.eq    .Lcheck_package
    cmp     w8, #0x4000             // AUDIO_DEVICE_OUT_USB_DEVICE
    b.eq    .Lcheck_package
    mov     w9, #0x04000000         // AUDIO_DEVICE_OUT_USB_HEADSET
    cmp     w8, w9
    b.ne    .Lreturn_to_policy

.Lcheck_package:
    // AudioPolicyManager::mCurrentPackageName is an Android String16 at +0x480.
    ldr     x0, [x26, #0x480]
    cbz     x0, .Lreturn_to_policy
    adr     x1, .Lapple_name
    bl      .Lutf16_equal
    cbnz    w0, .Lcheck_owner
    ldr     x0, [x26, #0x480]
    adr     x1, .Lnetease_name
    bl      .Lutf16_equal
    cbz     w0, .Lreturn_to_policy

.Lcheck_owner:
    // Query the current PreferredMixerAttributesInfo directly so that repeated
    // AudioTracks from the same UID do not replace it and reset active counts.
    // The returned sp<> uses x8 as its hidden result address.
    add     x8, sp, #0x28
    str     xzr, [sp, #0x28]
    mov     x0, x26
    mov     w1, w23
    ldr     w2, [sp, #0x20]
    mov     w3, wzr
    bl      GET_PREFERRED_INFO
    ldr     x19, [sp, #0x28]
    cbz     x19, .Linstall_preference

    ldr     w20, [x19, #0x14]
    // Release the temporary strong reference with the same identity address
    // used for the hidden sp<> result.
    mov     x0, x19
    add     x1, sp, #0x28
    bl      REFBASE_DEC_STRONG_PLT
    cmp     w20, w24
    b.eq    .Lreturn_to_policy

.Linstall_preference:
    // audio_mixer_attributes_t: 48 kHz, stereo, PCM32, DEFAULT behavior.
    // The fixed configuration opens hifi_playback; Xiaomi's native manager
    // subsequently changes the HAL/Mixer rate from actual playback events.
    mov     w8, #48000
    str     w8, [sp, #0x30]
    mov     w8, #3
    stp     w8, w8, [sp, #0x34]
    str     wzr, [sp, #0x3c]
    mov     x0, x26
    mov     x1, x27
    mov     w2, w23
    mov     w3, w24
    add     x4, sp, #0x30
    bl      SET_PREFERRED_ATTRIBUTES

.Lreturn_to_policy:
    ldr     x2, [sp, #0x20]
    ldp     x20, x19, [sp, #0x10]
    ldp     x29, x30, [sp, #0x00]
    add     sp, sp, #0x50
    sub     x8, x29, #0xf0
    b       GET_OUTPUT_HOOK_RETURN

// x0 = UTF-16 package, x1 = zero-terminated UTF-16 literal; w0 = equal.
.Lutf16_equal:
    ldrh    w8, [x0], #2
    ldrh    w9, [x1], #2
    cmp     w8, w9
    b.ne    .Lutf16_not_equal
    cbnz    w8, .Lutf16_equal
    mov     w0, #1
    ret
.Lutf16_not_equal:
    mov     w0, wzr
    ret

.p2align 1
.Lapple_name:
    .hword  'c','o','m','.','a','p','p','l','e','.','a','n','d','r','o','i','d','.','m','u','s','i','c',0
.Lnetease_name:
    .hword  'c','o','m','.','n','e','t','e','a','s','e','.','c','l','o','u','d','m','u','s','i','c',0
