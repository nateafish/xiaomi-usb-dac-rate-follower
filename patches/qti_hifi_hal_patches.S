// Exact-firmware AArch64 patches for Qualcomm's AIDL audio core HAL.
//
// Xiaomi's legacy HIFI policy changes an already-open stream with the vendor
// "sampling_rate" parameter. The Qualcomm HAL must permit PAL device
// reconfiguration for the HIFI usecase (enum 3).
//
// The frame-count function must remain stock. APM opens hifi_playback at
// 48 kHz, so QTI's original rate * 40 / 1000 calculation naturally creates
// the correct 1920-frame immutable FMQ.

.extern HIFI_USECASE_SKIP_RECONFIGURE

.section .hifi_frame_count_stock, "a"
.p2align 2
.global hifi_frame_count_stock
hifi_frame_count_stock:
    // Original HifiPlayback::getFrameCount() body after getSampleRate().
    .inst   0x93407c08
    .inst   0x52800509
    .inst   0x9bc97d09
    .inst   0xeb0903ff
    .inst   0x540001c1
    .inst   0x8b20c908

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
