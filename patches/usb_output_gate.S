// Exact-firmware AArch64 transport gate for Xiaomi/nezha OS4.0.0.15.
//
// HifiSampleRateManager's callback receives an audio_io_handle_t, but Xiaomi's
// stock sendkeySamplingRateToAHal() forwards sampling_rate to that output
// without checking its routed device.  This final sender-side gate permits the
// write only when every device currently routed on that exact output is USB.
// Lookup failure, an empty route, Bluetooth, speaker, wired, or a mixed
// USB/Bluetooth route all fail closed and return without touching the HAL.

.extern SENDKEY_BODY
.extern SENDKEY_ZERO_PATH

.section .usb_output_gate_branch, "ax"
.p2align 2
.global usb_output_gate_branch
usb_output_gate_branch:
    b       usb_output_gate

.section .usb_output_gate_cave, "ax"
.p2align 2
.global usb_output_gate

// Entry at AudioPolicyManager::sendkeySamplingRateToAHal + 4:
//   x0 = AudioPolicyManager*, w1 = output handle, w2 = requested rate
// Only caller-saved scratch registers are used and x0..x2 remain intact.
usb_output_gate:
    cbz     w2, SENDKEY_ZERO_PATH

    // mOutputs is a DefaultKeyedVector<audio_io_handle_t,
    // sp<SwAudioOutputDescriptor>> at AudioPolicyManager + 0xa8.
    add     x8, x0, #0xa8
    ldr     x9, [x8, #0x10]        // number of 16-byte key/value entries
    cbz     x9, .Ldeny
    ldr     x8, [x8, #0x8]         // entry array
    cbz     x8, .Ldeny
.Lfind_output:
    ldr     w10, [x8]
    cmp     w10, w1
    b.eq    .Loutput_found
    add     x8, x8, #0x10
    subs    x9, x9, #1
    b.ne    .Lfind_output
    b       .Ldeny

.Loutput_found:
    ldr     x10, [x8, #0x8]        // SwAudioOutputDescriptor*
    cbz     x10, .Ldeny

    // Non-duplicating SwAudioOutputDescriptor::devices() returns the
    // DeviceVector stored at +0xe8. Its item pointer and size are +8/+0x10.
    ldr     x9, [x10, #0xf8]
    cbz     x9, .Ldeny
    ldr     x10, [x10, #0xf0]
    cbz     x10, .Ldeny

.Lcheck_device:
    ldr     x11, [x10], #0x8       // DeviceDescriptor*
    cbz     x11, .Ldeny
    ldr     w12, [x11, #0x148]     // audio_devices_t
    mov     w13, #0x2000           // AUDIO_DEVICE_OUT_USB_ACCESSORY
    cmp     w12, w13
    b.eq    .Lnext_device
    mov     w13, #0x4000           // AUDIO_DEVICE_OUT_USB_DEVICE
    cmp     w12, w13
    b.eq    .Lnext_device
    mov     w13, #0x04000000       // AUDIO_DEVICE_OUT_USB_HEADSET
    cmp     w12, w13
    b.ne    .Ldeny
.Lnext_device:
    subs    x9, x9, #1
    b.ne    .Lcheck_device
    b       SENDKEY_BODY

.Ldeny:
    ret
