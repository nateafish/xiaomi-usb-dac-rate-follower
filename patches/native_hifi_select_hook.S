// Exact-firmware AArch64 hooks for Xiaomi/nezha OS4.0.0.15.XPACNXM.
//
// The routing hook runs at the existing AOSP -> Xiaomi selectOutput callback.
// Xiaomi's callback is executed first and its result is preserved unless all
// of these fail-closed conditions are true:
//   * package is Apple Music or NetEase Cloud Music;
//   * Xiaomi/AOSP selected an output currently routed only to USB;
//   * an open, USB-routed, non-duplicating hifi_playback descriptor exists.
//
// No PreferredMixerAttributesInfo is created, no output is reopened here, and
// no persistent state or counter is added.  The selected output handle alone
// is changed, leaving Xiaomi's native HifiSampleRateManager to process normal
// start/stop events and reconfigure the HIFI MixerThread in place.

.extern VENDOR_SELECT_OUTPUT_STUB
.extern SELECT_OUTPUT_RETURN
.extern HIFI_APP_STOCK_CONTINUE
.extern LATEST_MAX_TRUE_RETURN
.extern LATEST_MAX_RATE_CONTINUE
.extern LATEST_MAX_RATE_EMPTY_RETURN
.extern PROFILE_ALL_STOPPED
.extern HIFI_IDLE_RATE_STOCK
.extern HIFI_IDLE_RATE_CONTINUE

.section .select_output_branch, "ax"
.p2align 2
.global select_output_branch
select_output_branch:
    b       native_hifi_select_hook

.section .hifi_app_branch, "ax"
.p2align 2
.global hifi_app_branch
hifi_app_branch:
    b       native_hifi_app_filter

.section .latest_max_final_stop_patch, "ax"
.p2align 2
.global latest_max_final_stop_patch
latest_max_final_stop_patch:
    // The final-stop path has already loaded the retained rate-tree node into
    // w22 before it checks the application-count list.  That node can be the
    // synthetic 384 kHz default, so changing getActiveSampleRate() alone is
    // too late.  Replace it only for the no-real-application branch, then
    // keep Xiaomi's normal hardware-update flow.
    b       latest_max_idle_transition

.section .latest_max_idle_rate_patch, "ax"
.p2align 2
.global latest_max_idle_rate_patch
latest_max_idle_rate_patch:
    // Xiaomi retains a synthetic 384 kHz rate node after the last real
    // application stops, so testing only the active-rate tree is insufficient.
    // Consult the existing application-count list before choosing an idle rate.
    b       latest_max_idle_rate

.section .hifi_idle_rate_branch, "ax"
.p2align 2
.global hifi_idle_rate_branch
hifi_idle_rate_branch:
    b       hifi_idle_rate_hook

.section .hifi_idle_rate_cave, "ax"
.p2align 2
.global hifi_idle_rate_hook
hifi_idle_rate_hook:
    // handlePlaybackEvent() has just updated LATEST_MAX.  Its following
    // inline tree lookup can still see Xiaomi's retained 384 kHz node after
    // the final stop.  Ask the existing lifecycle predicate before that
    // lookup; active applications continue through the stock path.
    cmp     w8, #1
    b.eq    HIFI_IDLE_RATE_FIRST_LOCK
    cbz     w25, HIFI_IDLE_RATE_STOCK
    add     x0, x27, #0x28
    bl      PROFILE_ALL_STOPPED
    cbz     w0, HIFI_IDLE_RATE_STOCK
    // Rate 1 is an internal final-stop handoff marker, never a HAL rate. The
    // sender gate converts it to 48 kHz only when another USB output is active;
    // otherwise it suppresses the hardware update until HIFI standby.
    mov     w26, #1
    b       HIFI_IDLE_RATE_CONTINUE

.section .native_hifi_cave, "ax"
.p2align 2
.global native_hifi_select_hook
.global native_hifi_app_filter

// Replaces the call at AudioPolicyManager::selectOutput + 0x968 (VA 0x57214).
// Live arguments are the exact vendor callback ABI:
//   x0 AudioPolicyManager*, x1 client interface, x2 String16 package,
//   x3 SwAudioOutputCollection*, x4 selected audio_io_handle_t*.
native_hifi_select_hook:
    sub     sp, sp, #0x20
    stp     x2, x3, [sp]
    str     x4, [sp, #0x10]
    bl      VENDOR_SELECT_OUTPUT_STUB
    ldp     x2, x3, [sp]
    ldr     x4, [sp, #0x10]

    cbz     x2, .Lselect_done
    cbz     x3, .Lselect_done
    cbz     x4, .Lselect_done
    ldr     x0, [x2]
    cbz     x0, .Lselect_done
    adr     x1, .Lapple_utf16
    bl      .Lutf16_equal
    cbnz    w0, .Lpackage_allowed
    ldr     x0, [x2]
    adr     x1, .Lnetease_utf16
    bl      .Lutf16_equal
    cbz     w0, .Lselect_done

.Lpackage_allowed:
    // Validate the collection before scanning its 16-byte key/value items.
    ldr     x11, [x3, #0x10]
    cbz     x11, .Lselect_done
    cmp     x11, #64
    b.hi    .Lselect_done
    ldr     x12, [x3, #0x8]
    cbz     x12, .Lselect_done
    ldr     w13, [x4]

    // The ordinary selected output must itself currently route only to USB.
.Lfind_selected:
    ldr     w14, [x12]
    cmp     w14, w13
    b.eq    .Lselected_found
    add     x12, x12, #0x10
    subs    x11, x11, #1
    b.ne    .Lfind_selected
    b       .Lselect_done

.Lselected_found:
    ldr     x0, [x12, #0x8]
    cbz     x0, .Lselect_done
    ldr     x6, [x0, #0x1d0]
    cbz     x6, .Lselect_done
    bl      .Lis_usb_only_output
    cbz     w0, .Lselect_done

    // Locate the real hifi_playback IOProfile by name.  mProfile is at +0x1d0;
    // a duplicating output has no profile and therefore fails closed here.
    ldr     x11, [x3, #0x10]
    ldr     x12, [x3, #0x8]
.Lfind_hifi:
    ldr     x14, [x12, #0x8]
    cbz     x14, .Lnext_output
    ldr     x15, [x14, #0x1d0]
    cbz     x15, .Lnext_output

    // Android libc++ std::string: short data at +1, long data pointer at +16.
    ldrb    w6, [x15, #0x30]
    add     x0, x15, #0x31
    ldr     x7, [x15, #0x40]
    tst     w6, #1
    csel    x0, x0, x7, eq
    cbz     x0, .Lnext_output
    adr     x1, .Lhifi_name
    bl      .Lascii_equal
    cbz     w0, .Lnext_output

    // Require the HIFI descriptor's current route to be USB too.  This rejects
    // stale/empty descriptors and makes Bluetooth/speaker coexistence inert.
    mov     x0, x14
    bl      .Lis_usb_only_output
    cbz     w0, .Lselect_done
    ldr     w16, [x12]
    str     w16, [x4]
    b       .Lselect_done

.Lnext_output:
    add     x12, x12, #0x10
    subs    x11, x11, #1
    b.ne    .Lfind_hifi

.Lselect_done:
    add     sp, sp, #0x20
    b       SELECT_OUTPUT_RETURN

// Entry hook for HifiSampleRateManager::isAppAllowed() at VA 0xd3bcc.
// Only hifi_playback gets the exact two-package policy. Other profile names
// replay the displaced PAC instruction and continue through Xiaomi's body.
native_hifi_app_filter:
    cbz     x0, .Lapp_stock
    ldrb    w8, [x0]
    add     x9, x0, #1
    ldr     x10, [x0, #0x10]
    tst     w8, #1
    csel    x8, x9, x10, eq
    cbz     x8, .Lapp_stock
    adr     x9, .Lhifi_name
.Lprofile_compare:
    ldrb    w10, [x8], #1
    ldrb    w11, [x9], #1
    cmp     w10, w11
    b.ne    .Lapp_stock
    cbnz    w10, .Lprofile_compare

    // This path returns directly, so preserve the caller's LR around helpers.
    sub     sp, sp, #0x10
    str     x30, [sp]
    cbz     x1, .Lapp_deny
    str     x1, [sp, #0x8]
    ldrb    w8, [x1]
    add     x0, x1, #1
    ldr     x9, [x1, #0x10]
    tst     w8, #1
    csel    x0, x0, x9, eq
    cbz     x0, .Lapp_deny
    adr     x1, .Lapple_name
    bl      .Lascii_equal
    cbnz    w0, .Lapp_return
    // Reload the original application std::string from the spare frame slot.
    ldr     x1, [sp, #0x8]
    ldrb    w8, [x1]
    add     x0, x1, #1
    ldr     x9, [x1, #0x10]
    tst     w8, #1
    csel    x0, x0, x9, eq
    cbz     x0, .Lapp_deny
    adr     x1, .Lnetease_name
    bl      .Lascii_equal
    b       .Lapp_return

.Lapp_deny:
    mov     w0, wzr
.Lapp_return:
    ldr     x30, [sp]
    add     sp, sp, #0x10
    ret

.Lapp_stock:
    paciasp
    b       HIFI_APP_STOCK_CONTINUE

// x0 UTF-16 data, x1 zero-terminated UTF-16 literal; returns w0 boolean.
.Lutf16_equal:
    ldrh    w6, [x0], #2
    ldrh    w7, [x1], #2
    cmp     w6, w7
    b.ne    .Lnot_equal
    cbnz    w6, .Lutf16_equal
    mov     w0, #1
    ret

// x0 byte data, x1 zero-terminated byte literal; returns w0 boolean.
.Lascii_equal:
    ldrb    w2, [x0], #1
    ldrb    w6, [x1], #1
    cmp     w2, w6
    b.ne    .Lnot_equal
    cbnz    w2, .Lascii_equal
    mov     w0, #1
    ret
.Lnot_equal:
    mov     w0, wzr
    ret

// x0 SwAudioOutputDescriptor*; returns w0=1 only for a non-empty route whose
// every current DeviceDescriptor is one of the three Android USB output types.
.Lis_usb_only_output:
    cbz     x0, .Lusb_false
    ldr     x6, [x0, #0xf8]
    cbz     x6, .Lusb_false
    cmp     x6, #16
    b.hi    .Lusb_false
    ldr     x7, [x0, #0xf0]
    cbz     x7, .Lusb_false
.Lusb_loop:
    ldr     x8, [x7], #8
    cbz     x8, .Lusb_false
    ldr     w9, [x8, #0x148]
    cmp     w9, #0x2000
    b.eq    .Lusb_next
    cmp     w9, #0x4000
    b.eq    .Lusb_next
    mov     w10, #0x04000000
    cmp     w9, w10
    b.ne    .Lusb_false
.Lusb_next:
    subs    x6, x6, #1
    b.ne    .Lusb_loop
    mov     w0, #1
    ret
.Lusb_false:
    mov     w0, wzr
    ret

.p2align 1
.Lapple_utf16:
    .hword  'c','o','m','.','a','p','p','l','e','.','a','n','d','r','o','i','d','.','m','u','s','i','c',0
.Lnetease_utf16:
    .hword  'c','o','m','.','n','e','t','e','a','s','e','.','c','l','o','u','d','m','u','s','i','c',0
.Lhifi_name:
    .asciz  "hifi_playback"
.Lapple_name:
    .asciz  "com.apple.android.music"
.Lnetease_name:
    .asciz  "com.netease.cloudmusic"

.p2align 2
.global latest_max_idle_rate
latest_max_idle_rate:
    // Mirror areAllApplicationsStopped(): the intrusive list at +0x50 may
    // contain zero-count nodes, so scan until a real application count is
    // found.  x8 still contains the active-rate tree size loaded by the
    // displaced instruction immediately before the hook.
    ldr     x9, [x0, #0x50]
.Lidle_application_loop:
    cbz     x9, .Lidle_return_48
    ldr     w10, [x9, #0x14]
    cmp     w10, #1
    b.ge    .Lidle_stock_rate
    ldr     x9, [x9]
    b       .Lidle_application_loop

.Lidle_stock_rate:
    // A real application is still active: preserve Xiaomi's original
    // LATEST_MAX lookup, including its stock empty-tree fallback.
    cbz     x8, LATEST_MAX_RATE_EMPTY_RETURN
    b       LATEST_MAX_RATE_CONTINUE

.Lidle_return_48:
    mov     w0, #48000
    ret

.p2align 2
.global latest_max_idle_transition
latest_max_idle_transition:
    // w22 is the rate selected by updateLatestMaxStrategy().  At this point
    // the application-count list is empty, so the only valid idle rate is the
    // ordinary USB mixer rate.  The caller still needs a true change result
    // to send it through the native callback.
    mov     w22, #48000
    b       LATEST_MAX_TRUE_RETURN
