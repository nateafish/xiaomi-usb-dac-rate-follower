.section .latest_max_patch, "a"
.p2align 2
.global latest_max_patch
latest_max_patch:
    // mov w3, wzr: ProfileManager::initialize(..., LATEST_MAX = 0)
    .inst 0x2a1f03e3

.section .flinger_sync_patch, "a"
.p2align 2
.global flinger_sync_patch
flinger_sync_patch:
    // b 0x1b0c2c from 0x1b0a84: readOutputParameters_l(true)
    .inst 0x1400006a
