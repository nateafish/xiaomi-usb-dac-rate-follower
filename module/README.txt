Xiaomi USB DAC Rate Follower v0.7.6-alpha

Experimental module for Xiaomi 17 Ultra Android 17 firmware
OS4.0.0.15.XPACNXM.

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

The installer checks the exact firmware fingerprint, ELF architecture, code
context and patch locations. It aborts on unsupported or mixed patch states.

Output target: sample-rate following. Strict Bit Perfect is outside the
project's guarantee.

KernelSU requires an active metamodule. Reboot after installation.
