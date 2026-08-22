Xiaomi 17 USB Whitelist Rate Follower v0.3.1-alpha

Default targets:
  com.apple.android.music
  com.netease.cloudmusic

This build enables Xiaomi's built-in deep-buffer sample-rate manager and adds
44.1 kHz to the normal mixer. It uses no Zygisk or app injection.

IMPORTANT: sample-rate following is verified, but bit-perfect output is not.
The module does not yet prove that every effect, gain, and processing stage is
removed. Install only on the supported Xiaomi 17 firmware; the installer
checks the Qualcomm USB library hash and aborts on a mismatch.
