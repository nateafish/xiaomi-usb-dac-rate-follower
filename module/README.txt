Xiaomi USB DAC Rate Follower v0.5.1-alpha

This build keeps the firmware-locked Qualcomm USB capability patch that puts
44.1 kHz inside the vendor HAL's seven-rate list. It marks Xiaomi's existing
dynamic hifi_playback port BIT_PERFECT and injects only Apple Music and NetEase
Cloud Music through Zygisk.

Immediately before a target app creates a PCM media AudioTrack, the module asks
Android 17 for a PCM32 preferred USB mixer matching that track's actual sample
rate and channel mask. Preference-only AudioAttributes omit the apps' DEEP_BUFFER
flag so that Android can match the BIT_PERFECT hifi profile. The original
AudioTrack and its buffers remain unchanged; AudioFlinger performs any required
source-to-PCM32 conversion.

There is no polling daemon, system AudioPolicyManager binary patch, live audio
service restart, or modification of ordinary apps' 48 kHz mixer. KernelSU users
must provide Zygisk Next or another compatible Zygisk implementation.

EXPERIMENTAL: bit-perfect and 44.1 -> 48 -> 96 kHz transitions still require
phased hardware verification. Keep a recovery path that can disable the module.
