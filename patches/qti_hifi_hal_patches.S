// Exact-firmware AArch64 patches for Qualcomm's AIDL audio core HAL.
//
// Xiaomi's legacy HIFI policy changes an already-open stream with the vendor
// "sampling_rate" parameter.  The Qualcomm HAL must therefore do two things:
//   1. permit PAL device reconfiguration for the HIFI usecase (enum 3); and
//   2. avoid sizing the immutable AIDL FMQ from the profile's initial 384 kHz
//      sample rate, which otherwise leaves 15360 frames (320-348 ms) after a
//      later 48/44.1 kHz in-place rate change.

.extern HIFI_FRAME_COUNT_EPILOGUE
.extern HIFI_USECASE_SKIP_RECONFIGURE

.section .hifi_frame_count_cap_patch, "ax"
.p2align 2
.global hifi_frame_count_cap_patch
hifi_frame_count_cap_patch:
    // Entry replaces HifiPlayback::getFrameCount() after getSampleRate() has
    // returned a valid sample rate in w0. Return min(rate, 48000) / 25:
    // 1764 frames at 44.1 kHz, 1920 frames at 48 kHz and 1920 above 48 kHz.
    // This keeps the fixed FMQ near 40 ms at low rates and no larger than that.
    mov     w8, #48000
    cmp     w0, w8
    csel    w0, w0, w8, lo
    mov     w8, #25
    udiv    w0, w0, w8
    b       HIFI_FRAME_COUNT_EPILOGUE

.section .hifi_usecase_reconfigure_patch, "ax"
.p2align 2
.global hifi_usecase_reconfigure_patch
hifi_usecase_reconfigure_patch:
    // Stock accepts usecases 8 and 13. Include enum 3, the HIFI stream used on
    // this firmware, then continue through the original PAL-handle guard.
    mov     w9, #0x2108           // bits 3, 8 and 13
    lsr     w9, w9, w8
    tbz     w9, #0, HIFI_USECASE_SKIP_RECONFIGURE
    nop
