.extern HIFI_USECASE_SKIP_RECONFIGURE

.section .a16_qti_hifi_reconfigure, "ax"
.p2align 2
.global a16_qti_hifi_reconfigure
a16_qti_hifi_reconfigure:
    cmp     w8, #13
    b.eq    .Lcontinue
    cmp     w8, #3
    b.ne    HIFI_USECASE_SKIP_RECONFIGURE
.Lcontinue:
