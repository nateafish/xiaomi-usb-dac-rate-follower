Xiaomi USB DAC Rate Follower v0.5.0-alpha

This build keeps the firmware-locked Qualcomm USB capability patch that puts
44.1 kHz inside the vendor HAL's seven-rate list. It marks Xiaomi's existing
dynamic hifi_playback port BIT_PERFECT and injects only Apple Music and NetEase
Cloud Music through Zygisk.

Immediately before a target app creates a PCM media AudioTrack, the module asks
Android 17 for a preferred USB mixer matching that track's actual sample rate,
encoding, and channel mask. The original AudioTrack setup then runs unchanged.

There is no polling daemon, system AudioPolicyManager binary patch, live audio
service restart, or modification of ordinary apps' 48 kHz mixer. KernelSU users
must provide Zygisk Next or another compatible Zygisk implementation.

EXPERIMENTAL: bit-perfect and 44.1 -> 48 -> 96 kHz transitions still require
phased hardware verification. Keep a recovery path that can disable the module.
