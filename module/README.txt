Xiaomi USB DAC Rate Follower v0.7.8-alpha

Experimental module verified on Xiaomi 17 Ultra Android 17 firmware
OS4.0.0.15.XPACNXM. Other Qualcomm Android 17 AIDL baselines are allowed only
when all semantic ELF and layout checks match, and are reported as unverified.

Supported players:
- com.apple.android.music
- com.netease.cloudmusic

Supported output:
- USB Audio only
- PCM32 HIFI playback
- 44.1, 48, 88.2, 96, 176.4, 192 and 384 kHz

The module uses Xiaomi's native HifiSampleRateManager and contains no daemon,
polling loop, Zygisk code or application hook. Speaker, Bluetooth, analogue
and mixed routes are left untouched.

When the final HIFI track stops, an idle USB DAC keeps the last source rate
until standby instead of being switched to 48 kHz first. If another ordinary
USB output is already active, the shared backend is handed back to 48 kHz.

The installer checks the ELF architecture, unique code context, object layout
and patch space. Fingerprints and whole-file hashes are diagnostic only. It
aborts on unsupported or mixed patch states.

Patch locations, imported calls and AArch64 branch targets are resolved from
the installed ELF at runtime. Recorded research offsets are not write gates.
The bundled Android 16 use cases are offline-validated but installation is
blocked until hardware testing is complete.

After a system-partition OTA, uninstall the old module, reboot into the stock
system, then reinstall. A cross-system in-place update is left untouched and
aborted. Same-system updates use Magisk's stock mirror or the active KernelSU
module payload; full stock libraries are not stored in this module.

Output target: sample-rate following. Strict Bit Perfect is outside the
project's guarantee.

KernelSU requires an active metamodule. Reboot after installation.
