#!/system/bin/sh

. "$TARGET_DIR/usecases/native-hifi-route.conf"
. "$TARGET_DIR/usecases/hifi-dynamic-default.conf"
. "$TARGET_DIR/usecases/mixer-hal-sync.conf"
. "$TARGET_DIR/usecases/usb-441-rate-table.conf"
. "$TARGET_DIR/usecases/qti-hifi-reconfigure.conf"
. "$TARGET_DIR/usecases/pudding-sampling-rate-handler.conf"
. "$TARGET_DIR/usecases/shifted-pointer-rate-handler.conf"
. "$TARGET_DIR/usecases/dada-sampling-rate-handler.conf"
. "$MODPATH/patches/a16_native_hifi_route.relocations.conf" \
    || abort "! Missing Android 16 native HIFI relocation manifest"
. "$MODPATH/patches/a16_dada_rate_parameter.relocations.conf" \
    || abort "! Missing Xiaomi 15 parameter relocation manifest"
. "$MODPATH/patches/a16_dada_rate_worker.relocations.conf" \
    || abort "! Missing Xiaomi 15 worker relocation manifest"
. "$MODPATH/patches/a16_pointer_rate.relocations.conf" \
    || abort "! Missing Android 16 pointer-rate relocation manifest"
. "$MODPATH/patches/a16_pointer_rate_worker.relocations.conf" \
    || abort "! Missing Android 16 pointer-rate worker relocation manifest"
. "$MODPATH/patches/a16_shifted_pointer_rate.relocations.conf" \
    || abort "! Missing Android 16 shifted pointer-rate relocation manifest"
. "$MODPATH/patches/a16_shifted_pointer_rate_worker.relocations.conf" \
    || abort "! Missing Android 16 shifted pointer-rate worker relocation manifest"
. "$MODPATH/lib/elf-runtime.sh"

apply_target_patches() {
    ui_print "- Resolving Android 16 use cases by semantic signatures"

    ep_find "$IMPL_SOURCE" "$ROUTE_COLLECTION_DOMAIN" \
        "$ROUTE_COLLECTION_LAYOUT" 'SwAudioOutputCollection layout' >/dev/null \
        || abort "! Android 16 output-collection layout is incompatible"
    ep_find "$IMPL_SOURCE" "$ROUTE_DEVICES_DOMAIN" \
        "$ROUTE_DEVICES_LAYOUT" 'AudioOutputDescriptor device-vector layout' >/dev/null \
        || abort "! Android 16 device-vector layout is incompatible"
    ep_find "$IMPL_SOURCE" "$ROUTE_PROFILE_DOMAIN" \
        "$ROUTE_PROFILE_LAYOUT" 'SwAudioOutputDescriptor profile layout' >/dev/null \
        || abort "! Android 16 output-profile layout is incompatible"
    ep_find "$IMPL_SOURCE" "$ROUTE_NAME_DOMAIN" \
        "$ROUTE_NAME_LAYOUT" 'IOProfile name layout' >/dev/null \
        || abort "! Android 16 IOProfile layout is incompatible"
    ep_find "$IMPL_SOURCE" "$ROUTE_TYPE_DOMAIN" \
        "$ROUTE_TYPE_LAYOUT" 'DeviceDescriptor type layout' >/dev/null \
        || abort "! Android 16 DeviceDescriptor layout is incompatible"

    select_match=$(ep_find "$POLICY_DEST" exec "$ROUTE_SELECT_CONTEXT" \
        'native selectOutput call site') || abort "! Cannot resolve Android 16 selectOutput"
    SELECT_SITE=$(offset_add "$select_match" "$ROUTE_SELECT_SITE_DELTA")
    cave_anchor=$(ep_find "$POLICY_DEST" exec "$ROUTE_CAVE_ANCHOR" \
        'Android 16 executable-cave anchor') || abort "! Cannot resolve Android 16 executable cave"
    CFI_SLOWPATH=$(ep_plt "$POLICY_DEST" "$ROUTE_CAVE_ANCHOR_PLT" \
        'Android 16 CFI slowpath') || abort "! Cannot resolve Android 16 cave owner"
    branch_points_to "$POLICY_DEST" "$cave_anchor" "$CFI_SLOWPATH" \
        || abort "! Android 16 executable cave is not owned by the expected function tail"
    CAVE_BASE=$(ep_cave_after "$POLICY_DEST" "$cave_anchor" \
        "$ROUTE_CAVE_ANCHOR_SIZE" "$ROUTE_CAVE_REQUIRED_SIZE" \
        "$ROUTE_CAVE_ALIGNMENT" 'Android 16 executable-cave allocation') \
        || abort "! Cannot allocate the Android 16 executable cave"
    DEFAULT_CAVE=$(offset_add "$CAVE_BASE" "$HIFI_DEFAULT_CAVE_DELTA")
    VENDOR_SELECT=$(ep_plt "$POLICY_DEST" "$ROUTE_VENDOR_SELECT_PLT" \
        'Xiaomi selectOutput callback') || abort "! Cannot resolve Android 16 Xiaomi callback"

    default_match=$(ep_find "$POLICY_DEST" exec "$HIFI_DEFAULT_CONTEXT" \
        'Android 16 hifi_playback dynamic default') || abort "! Cannot resolve Android 16 HIFI default"
    DEFAULT_SITE=$(offset_add "$default_match" "$HIFI_DEFAULT_SITE_DELTA")
    require_call_or_hook_branch "$POLICY_DEST" "$SELECT_SITE" \
        "$VENDOR_SELECT" "$CAVE_BASE" 'Android 16 selectOutput hook'
    require_stock_or_hook_branch "$POLICY_DEST" "$DEFAULT_SITE" \
        "$HIFI_DEFAULT_STOCK" "$DEFAULT_CAVE" 'Android 16 HIFI default hook'

    $ELFPATCHER inject "$POLICY_DEST" "$CAVE_BASE" \
        "$MODPATH/patches/a16_native_hifi_route.template.bin" \
        "${A16_NATIVE_HIFI_VENDOR_SELECT_OUTPUT_STUB}:$VENDOR_SELECT" \
        "${A16_NATIVE_HIFI_SELECT_OUTPUT_RETURN}:$(offset_add "$SELECT_SITE" 4)" \
        || abort "! Android 16 native HIFI route injection failed"
    $ELFPATCHER inject "$POLICY_DEST" "$DEFAULT_CAVE" \
        "$MODPATH/patches/a16_hifi_dynamic_default.template.bin" \
        "68:B:$(offset_add "$DEFAULT_SITE" 4)" \
        || abort "! Android 16 HIFI default injection failed"
    $ELFPATCHER branch "$POLICY_DEST" "$SELECT_SITE" "$CAVE_BASE" B \
        || abort "! Android 16 selectOutput relocation failed"
    $ELFPATCHER branch "$POLICY_DEST" "$DEFAULT_SITE" "$DEFAULT_CAVE" B \
        || abort "! Android 16 HIFI default relocation failed"

    mixer_match=$(ep_find "$FLINGER_DEST" exec "$MIXER_SYNC_CONTEXT" \
        'Android 16 MixerThread HAL-rate branch') || abort "! Cannot resolve Android 16 MixerThread"
    MIXER_SITE=$(offset_add "$mixer_match" "$MIXER_SYNC_SITE_DELTA")
    mixer_word=$($ELFPATCHER word "$FLINGER_DEST" "$MIXER_SITE") \
        || abort "! Cannot read Android 16 MixerThread branch"
    MIXER_TARGET=$(branch_target "$FLINGER_DEST" "$MIXER_SITE") \
        || abort "! Android 16 MixerThread target is not a branch"
    if [ $(( mixer_word & 0xff00001f )) -ne $(( 0x54000008 )) ] \
            && [ $(( mixer_word & 0xfc000000 )) -ne $(( 0x14000000 )) ]; then
        abort "! Unknown Android 16 MixerThread branch state"
    fi
    $ELFPATCHER branch "$FLINGER_DEST" "$MIXER_SITE" "$MIXER_TARGET" B \
        || abort "! Android 16 MixerThread relocation failed"

    usb_domain="symbol:$USB_RATE_SYMBOL"
    if $ELFPATCHER find "$USB_DEST" "$usb_domain" "$USB_RATE_PATCHED" \
            >/dev/null 2>&1; then
        :
    elif $ELFPATCHER find "$USB_DEST" "$usb_domain" "$USB_RATE_STOCK" \
            >/dev/null 2>&1; then
        $ELFPATCHER replace "$USB_DEST" "$usb_domain" "$USB_RATE_STOCK" 0 \
            "$USB_RATE_PATCHED" >/dev/null \
            || abort "! Android 16 Qualcomm USB table replacement failed"
    else
        abort "! Android 16 Qualcomm USB rate table is unknown or ambiguous"
    fi

    HAL_PATCH_KIND=
    if dada_match=$($ELFPATCHER find "$HAL_DEST" \
            "symbol:$DADA_RATE_FUNCTION" "$DADA_RATE_CONTEXT" 2>/dev/null) \
            && dada_worker_match=$($ELFPATCHER find "$HAL_DEST" \
                "symbol:$DADA_TRANSFER_FUNCTION" \
                "$DADA_WORKER_CONTEXT" 2>/dev/null); then
        HAL_PATCH_KIND=dada-worker-rate-handler
    elif qti_match=$($ELFPATCHER find "$HAL_DEST" exec \
            "$QTI_RECONFIG_CONTEXT" 2>/dev/null); then
        qti_state=stock
        HAL_PATCH_KIND=nezha-usecase-guard
    elif qti_match=$($ELFPATCHER find "$HAL_DEST" exec \
            "$QTI_RECONFIG_PATCHED_CONTEXT" 2>/dev/null); then
        qti_state=patched
        HAL_PATCH_KIND=nezha-usecase-guard
    elif pudding_match=$($ELFPATCHER find "$HAL_DEST" \
            "symbol:$PUDDING_RATE_FUNCTION" \
            "$PUDDING_RATE_CONTEXT" 2>/dev/null) \
            && pudding_worker_match=$($ELFPATCHER find "$HAL_DEST" \
                "symbol:$PUDDING_TRANSFER_FUNCTION" \
                "$PUDDING_WORKER_CONTEXT" 2>/dev/null); then
        HAL_PATCH_KIND=a16-pointer-rate-handler
    elif shifted_match=$($ELFPATCHER find "$HAL_DEST" \
            "symbol:$SHIFTED_RATE_FUNCTION" \
            "$SHIFTED_RATE_CONTEXT" 2>/dev/null) \
            && shifted_worker_match=$($ELFPATCHER find "$HAL_DEST" \
                "symbol:$SHIFTED_TRANSFER_FUNCTION" \
                "$SHIFTED_WORKER_CONTEXT" 2>/dev/null); then
        HAL_PATCH_KIND=a16-shifted-pointer-rate-handler
    else
        abort "! Android 16 Qualcomm HAL layout is unsupported"
    fi

    case "${BASELINE_PATCH_PROFILE:-}:$HAL_PATCH_KIND" in
        policy-hifi-with-dada-worker-rate-handler:dada-worker-rate-handler|\
        policy-hifi-with-pointer-rate-handler:a16-pointer-rate-handler|\
        policy-hifi-with-shifted-pointer-rate-handler:a16-shifted-pointer-rate-handler|\
        native-hifi-usecase-guard:nezha-usecase-guard|'':*) ;;
        *) abort "! Recorded patch profile does not match the Qualcomm HAL layout" ;;
    esac

    if [ "$HAL_PATCH_KIND" = dada-worker-rate-handler ]; then
        ep_find "$HAL_DEST" "symbol:$DADA_CONFIGURE_FUNCTION" \
            "$DADA_PLATFORM_CONFIG_LAYOUT" \
            'Dada Platform/AudioPortConfig pointer layout' >/dev/null \
            || abort "! Dada Platform/AudioPortConfig layout is incompatible"
        ep_find "$HAL_DEST" "symbol:$DADA_RATE_FUNCTION" \
            "$DADA_CACHED_ATTR_LAYOUT" \
            'Dada cached PAL-attribute layout' >/dev/null \
            || abort "! Dada cached PAL-attribute layout is incompatible"
        ep_find "$HAL_DEST" \
            'symbol:_ZN3qti5audio4core16StreamOutPrimary7standbyEv' \
            "$DADA_USECASE_HANDLE_LAYOUT" \
            'Dada usecase/PAL-handle layout' >/dev/null \
            || abort "! Dada usecase/PAL-handle layout is incompatible"
        ep_find "$HAL_DEST" "symbol:$DADA_PLATFORM_RATE_FUNCTION" \
            "$DADA_SAMPLE_RATE_LAYOUT" \
            'Dada AudioPortConfig sample-rate layout' >/dev/null \
            || abort "! Dada AudioPortConfig sample-rate layout is incompatible"
        ep_find "$HAL_DEST" "symbol:$DADA_PLATFORM_RATE_FUNCTION" \
            "$DADA_PAL_RATE_LAYOUT" \
            'Dada PAL sample-rate layout' >/dev/null \
            || abort "! Dada PAL sample-rate layout is incompatible"

        DADA_RATE_SITE=$(offset_add "$dada_match" "$DADA_RATE_SITE_DELTA")
        DADA_WORKER_SITE=$(offset_add "$dada_worker_match" \
            "$DADA_WORKER_SITE_DELTA")
        dada_cave_anchor=$(ep_find "$HAL_DEST" exec "$DADA_CAVE_ANCHOR" \
            'Dada linker-gap owner') \
            || abort "! Cannot resolve the Dada executable-gap owner"
        DADA_CAVE_BASE=$(offset_add "$dada_cave_anchor" \
            "$DADA_CAVE_ANCHOR_SIZE")
        DADA_PARAMETER_CAVE=$(offset_add "$DADA_CAVE_BASE" \
            "$DADA_PARAMETER_CAVE_DELTA")
        DADA_WORKER_CAVE=$(offset_add "$DADA_CAVE_BASE" \
            "$DADA_WORKER_CAVE_DELTA")
        DADA_CAVE_OWNER=$(ep_plt "$HAL_DEST" "$DADA_CAVE_OWNER_PLT" \
            'Dada linker-gap owner call') \
            || abort "! Cannot resolve the Dada linker-gap owner call"
        branch_points_to "$HAL_DEST" \
            "$(offset_add "$dada_cave_anchor" \
                "$DADA_CAVE_OWNER_CALL_DELTA")" "$DADA_CAVE_OWNER" \
            || abort "! Dada executable gap is not owned by the expected function"

        dada_rate_stock=0
        dada_worker_stock=0
        hex_at "$HAL_DEST" "$DADA_RATE_SITE" "$DADA_RATE_STOCK" \
            && dada_rate_stock=1
        hex_at "$HAL_DEST" "$DADA_WORKER_SITE" "$DADA_WORKER_STOCK" \
            && dada_worker_stock=1
        if [ "$dada_rate_stock:$dada_worker_stock" = 1:1 ]; then
            resolved_dada_cave=$(ep_cave_after "$HAL_DEST" \
                "$dada_cave_anchor" "$DADA_CAVE_ANCHOR_SIZE" \
                "$DADA_CAVE_REQUIRED_SIZE" "$DADA_CAVE_ALIGNMENT" \
                'Dada sampling_rate executable cave') \
                || abort "! Cannot allocate the Dada sampling_rate cave"
            [ $(( resolved_dada_cave )) -eq $(( DADA_CAVE_BASE )) ] \
                || abort "! Dada linker-gap geometry changed unexpectedly"
        elif branch_points_to "$HAL_DEST" "$DADA_RATE_SITE" \
                "$DADA_PARAMETER_CAVE" \
                && branch_points_to "$HAL_DEST" "$DADA_WORKER_SITE" \
                    "$DADA_WORKER_CAVE"; then
            :
        else
            abort "! Unknown or mixed Xiaomi 15 sampling_rate hook state"
        fi

        DADA_STR_PARMS_GET_STR=$(ep_plt "$HAL_DEST" \
            "$DADA_STR_PARMS_GET_STR_PLT" 'Dada str_parms_get_str') \
            || abort "! Cannot resolve Dada str_parms_get_str"
        DADA_ATOI=$(ep_plt "$HAL_DEST" "$DADA_ATOI_PLT" 'Dada atoi') \
            || abort "! Cannot resolve Dada atoi"
        DADA_STANDBY=$(ep_symbol "$HAL_DEST" "$DADA_STANDBY_SYMBOL" \
            'Dada worker standby') || abort "! Cannot resolve Dada standby"

        $ELFPATCHER inject "$HAL_DEST" "$DADA_PARAMETER_CAVE" \
            "$MODPATH/patches/a16_dada_rate_parameter.template.bin" \
            "${A16_DADA_RATE_PARAMETER_DADA_STR_PARMS_GET_STR}:$DADA_STR_PARMS_GET_STR" \
            "${A16_DADA_RATE_PARAMETER_DADA_ATOI}:$DADA_ATOI" \
            "${A16_DADA_RATE_PARAMETER_DADA_RATE_RETURN}:$(offset_add "$DADA_RATE_SITE" 4)" \
            || abort "! Dada sampling_rate parameter injection failed"
        $ELFPATCHER inject "$HAL_DEST" "$DADA_WORKER_CAVE" \
            "$MODPATH/patches/a16_dada_rate_worker.template.bin" \
            "${A16_DADA_RATE_WORKER_DADA_STANDBY}:$DADA_STANDBY" \
            "${A16_DADA_RATE_WORKER_DADA_WORKER_RETURN}:$(offset_add "$DADA_WORKER_SITE" 4)" \
            || abort "! Dada sampling_rate worker injection failed"
        $ELFPATCHER branch "$HAL_DEST" "$DADA_RATE_SITE" \
            "$DADA_PARAMETER_CAVE" B \
            || abort "! Dada sampling_rate parameter hook failed"
        $ELFPATCHER branch "$HAL_DEST" "$DADA_WORKER_SITE" \
            "$DADA_WORKER_CAVE" B \
            || abort "! Dada sampling_rate worker hook failed"
    elif [ "$HAL_PATCH_KIND" = nezha-usecase-guard ]; then
        QTI_SITE=$(offset_add "$qti_match" "$QTI_RECONFIG_SITE_DELTA")
        if [ "$qti_state" = stock ]; then
            QTI_SKIP=$(branch_target "$HAL_DEST" "$(offset_add "$QTI_SITE" 4)") \
                || abort "! Cannot resolve stock Qualcomm skip target"
        else
            QTI_SKIP=$(branch_target "$HAL_DEST" "$(offset_add "$QTI_SITE" 12)") \
                || abort "! Cannot resolve Android 16 Qualcomm skip target"
        fi
        $ELFPATCHER patch-template "$HAL_DEST" "$QTI_SITE" \
            "$QTI_RECONFIG_STOCK" \
            "$MODPATH/patches/a16_qti_hifi_reconfigure.template.bin" \
            "12:COND19:$QTI_SKIP" \
            || abort "! Android 16 Qualcomm HIFI reconfiguration failed"
    else
        if [ "$HAL_PATCH_KIND" = a16-shifted-pointer-rate-handler ]; then
            POINTER_RATE_FUNCTION=$SHIFTED_RATE_FUNCTION
            POINTER_STANDBY_SYMBOL=$SHIFTED_STANDBY_SYMBOL
            POINTER_CONFIGURE_FUNCTION=$SHIFTED_CONFIGURE_FUNCTION
            POINTER_TRANSFER_FUNCTION=$SHIFTED_TRANSFER_FUNCTION
            POINTER_MATCH=$shifted_match
            POINTER_WORKER_MATCH=$shifted_worker_match
            POINTER_RATE_SITE_DELTA=$SHIFTED_RATE_SITE_DELTA
            POINTER_RATE_STOCK=$SHIFTED_RATE_STOCK
            POINTER_WORKER_SITE_DELTA=$SHIFTED_WORKER_SITE_DELTA
            POINTER_WORKER_STOCK=$SHIFTED_WORKER_STOCK
            POINTER_PLATFORM_CONFIG_LAYOUT=$SHIFTED_PLATFORM_CONFIG_LAYOUT
            POINTER_CACHED_ATTR_LAYOUT=$SHIFTED_CACHED_ATTR_LAYOUT
            POINTER_SAMPLE_RATE_LAYOUT=$SHIFTED_SAMPLE_RATE_LAYOUT
            POINTER_USECASE_TAG_LAYOUT=$SHIFTED_USECASE_TAG_LAYOUT
            POINTER_PAL_HANDLE_LAYOUT=$SHIFTED_PAL_HANDLE_LAYOUT
            POINTER_CAVE_ANCHOR=$SHIFTED_CAVE_ANCHOR
            POINTER_CAVE_ANCHOR_SIZE=$SHIFTED_CAVE_ANCHOR_SIZE
            POINTER_CAVE_REQUIRED_SIZE=$SHIFTED_CAVE_REQUIRED_SIZE
            POINTER_CAVE_ALIGNMENT=$SHIFTED_CAVE_ALIGNMENT
            POINTER_CAVE_OWNER_CALL_DELTA=$SHIFTED_CAVE_OWNER_CALL_DELTA
            POINTER_CAVE_OWNER_PLT=$SHIFTED_CAVE_OWNER_PLT
            POINTER_WORKER_CAVE_DELTA=$SHIFTED_WORKER_CAVE_DELTA
            POINTER_STR_PARMS_GET_STR_PLT=$SHIFTED_STR_PARMS_GET_STR_PLT
            POINTER_ATOI_PLT=$SHIFTED_ATOI_PLT
            POINTER_PAYLOAD=$MODPATH/patches/a16_shifted_pointer_rate_handler.template.bin
            POINTER_WORKER_PAYLOAD=$MODPATH/patches/a16_shifted_pointer_rate_worker.template.bin
            POINTER_RELOC_STR_PARMS_GET_STR=$A16_SHIFTED_POINTER_RATE_STR_PARMS_GET_STR
            POINTER_RELOC_ATOI=$A16_SHIFTED_POINTER_RATE_ATOI
            POINTER_RELOC_RATE_RETURN=$A16_SHIFTED_POINTER_RATE_PUDDING_RATE_RETURN
            POINTER_RELOC_WORKER_STANDBY=$A16_SHIFTED_POINTER_RATE_WORKER_PUDDING_WORKER_STANDBY
            POINTER_RELOC_WORKER_RETURN=$A16_SHIFTED_POINTER_RATE_WORKER_PUDDING_WORKER_RETURN
        else
            POINTER_RATE_FUNCTION=$PUDDING_RATE_FUNCTION
            POINTER_STANDBY_SYMBOL=$PUDDING_STANDBY_SYMBOL
            POINTER_CONFIGURE_FUNCTION=$PUDDING_CONFIGURE_FUNCTION
            POINTER_TRANSFER_FUNCTION=$PUDDING_TRANSFER_FUNCTION
            POINTER_MATCH=$pudding_match
            POINTER_WORKER_MATCH=$pudding_worker_match
            POINTER_RATE_SITE_DELTA=$PUDDING_RATE_SITE_DELTA
            POINTER_RATE_STOCK=$PUDDING_RATE_STOCK
            POINTER_WORKER_SITE_DELTA=$PUDDING_WORKER_SITE_DELTA
            POINTER_WORKER_STOCK=$PUDDING_WORKER_STOCK
            POINTER_PLATFORM_CONFIG_LAYOUT=$PUDDING_PLATFORM_CONFIG_LAYOUT
            POINTER_CACHED_ATTR_LAYOUT=$PUDDING_CACHED_ATTR_LAYOUT
            POINTER_SAMPLE_RATE_LAYOUT=$PUDDING_SAMPLE_RATE_LAYOUT
            POINTER_USECASE_TAG_LAYOUT=$PUDDING_USECASE_TAG_LAYOUT
            POINTER_PAL_HANDLE_LAYOUT=$PUDDING_PAL_HANDLE_LAYOUT
            POINTER_CAVE_ANCHOR=$PUDDING_CAVE_ANCHOR
            POINTER_CAVE_ANCHOR_SIZE=$PUDDING_CAVE_ANCHOR_SIZE
            POINTER_CAVE_REQUIRED_SIZE=$PUDDING_CAVE_REQUIRED_SIZE
            POINTER_CAVE_ALIGNMENT=$PUDDING_CAVE_ALIGNMENT
            POINTER_CAVE_OWNER_CALL_DELTA=$PUDDING_CAVE_OWNER_CALL_DELTA
            POINTER_CAVE_OWNER_PLT=$PUDDING_CAVE_OWNER_PLT
            POINTER_WORKER_CAVE_DELTA=$PUDDING_WORKER_CAVE_DELTA
            POINTER_STR_PARMS_GET_STR_PLT=$PUDDING_STR_PARMS_GET_STR_PLT
            POINTER_ATOI_PLT=$PUDDING_ATOI_PLT
            POINTER_PAYLOAD=$MODPATH/patches/a16_pudding_sampling_rate_handler.template.bin
            POINTER_WORKER_PAYLOAD=$MODPATH/patches/a16_pudding_rate_worker.template.bin
            POINTER_RELOC_STR_PARMS_GET_STR=$A16_POINTER_RATE_STR_PARMS_GET_STR
            POINTER_RELOC_ATOI=$A16_POINTER_RATE_ATOI
            POINTER_RELOC_RATE_RETURN=$A16_POINTER_RATE_PUDDING_RATE_RETURN
            POINTER_RELOC_WORKER_STANDBY=$A16_POINTER_RATE_WORKER_PUDDING_WORKER_STANDBY
            POINTER_RELOC_WORKER_RETURN=$A16_POINTER_RATE_WORKER_PUDDING_WORKER_RETURN
        fi

        ep_find "$HAL_DEST" "symbol:$POINTER_RATE_FUNCTION" \
            "$POINTER_PLATFORM_CONFIG_LAYOUT" \
            'Android 16 Platform/AudioPortConfig pointer layout' >/dev/null \
            || abort "! Android 16 Platform/AudioPortConfig layout is incompatible"
        ep_find "$HAL_DEST" "symbol:$POINTER_RATE_FUNCTION" \
            "$POINTER_CACHED_ATTR_LAYOUT" \
            'Android 16 cached PAL-attribute layout' >/dev/null \
            || abort "! Android 16 cached PAL-attribute layout is incompatible"
        ep_find "$HAL_DEST" "symbol:$POINTER_CONFIGURE_FUNCTION" \
            "$POINTER_SAMPLE_RATE_LAYOUT" \
            'Android 16 AudioPortConfig sample-rate layout' >/dev/null \
            || abort "! Android 16 sample-rate field is incompatible"
        ep_find "$HAL_DEST" "symbol:$POINTER_STANDBY_SYMBOL" \
            "$POINTER_USECASE_TAG_LAYOUT" \
            'Android 16 usecase-tag layout' >/dev/null \
            || abort "! Android 16 usecase tag is incompatible"
        ep_find "$HAL_DEST" \
            'symbol:_ZN3qti5audio4core16StreamOutPrimary7standbyEv' \
            "$POINTER_PAL_HANDLE_LAYOUT" \
            'Android 16 PAL-handle layout' >/dev/null \
            || abort "! Android 16 PAL handle is incompatible"

        PUDDING_RATE_SITE=$(offset_add "$POINTER_MATCH" \
            "$POINTER_RATE_SITE_DELTA")
        PUDDING_WORKER_SITE=$(offset_add "$POINTER_WORKER_MATCH" \
            "$POINTER_WORKER_SITE_DELTA")
        pudding_cave_anchor=$(ep_find "$HAL_DEST" exec \
            "$POINTER_CAVE_ANCHOR" 'Android 16 linker-gap owner') \
            || abort "! Cannot resolve the Android 16 executable-gap owner"
        PUDDING_CAVE_BASE=$(offset_add "$pudding_cave_anchor" \
            "$POINTER_CAVE_ANCHOR_SIZE")
        PUDDING_WORKER_CAVE=$(offset_add "$PUDDING_CAVE_BASE" \
            "$POINTER_WORKER_CAVE_DELTA")
        PUDDING_CAVE_OWNER=$(ep_plt "$HAL_DEST" \
            "$POINTER_CAVE_OWNER_PLT" 'Android 16 linker-gap owner call') \
            || abort "! Cannot resolve the Android 16 linker-gap owner call"
        branch_points_to "$HAL_DEST" \
            "$(offset_add "$pudding_cave_anchor" \
                "$POINTER_CAVE_OWNER_CALL_DELTA")" "$PUDDING_CAVE_OWNER" \
            || abort "! Android 16 executable gap has an unexpected owner"
        pointer_rate_stock=0
        pointer_worker_stock=0
        hex_at "$HAL_DEST" "$PUDDING_RATE_SITE" "$POINTER_RATE_STOCK" \
            && pointer_rate_stock=1
        hex_at "$HAL_DEST" "$PUDDING_WORKER_SITE" "$POINTER_WORKER_STOCK" \
            && pointer_worker_stock=1
        if [ "$pointer_rate_stock:$pointer_worker_stock" = 1:1 ]; then
            resolved_pudding_cave=$(ep_cave_after "$HAL_DEST" \
                "$pudding_cave_anchor" "$POINTER_CAVE_ANCHOR_SIZE" \
                "$POINTER_CAVE_REQUIRED_SIZE" "$POINTER_CAVE_ALIGNMENT" \
                'Android 16 sampling_rate executable cave') \
                || abort "! Cannot allocate the Android 16 sampling_rate cave"
            [ $(( resolved_pudding_cave )) -eq \
                    $(( PUDDING_CAVE_BASE )) ] \
                || abort "! Android 16 linker-gap geometry changed unexpectedly"
        elif branch_points_to "$HAL_DEST" "$PUDDING_RATE_SITE" \
                "$PUDDING_CAVE_BASE" \
                && branch_points_to "$HAL_DEST" "$PUDDING_WORKER_SITE" \
                    "$PUDDING_WORKER_CAVE"; then
            :
        else
            abort "! Unknown or mixed Android 16 sampling_rate hook state"
        fi

        PUDDING_STR_PARMS_GET_STR=$(ep_plt "$HAL_DEST" \
            "$POINTER_STR_PARMS_GET_STR_PLT" 'Android 16 str_parms_get_str') \
            || abort "! Cannot resolve Android 16 str_parms_get_str"
        PUDDING_ATOI=$(ep_plt "$HAL_DEST" "$POINTER_ATOI_PLT" \
            'Android 16 atoi') || abort "! Cannot resolve Android 16 atoi"
        PUDDING_STANDBY=$(ep_symbol "$HAL_DEST" "$POINTER_STANDBY_SYMBOL" \
            'Android 16 transfer-worker standby') \
            || abort "! Cannot resolve Android 16 transfer-worker standby"
        $ELFPATCHER inject "$HAL_DEST" "$PUDDING_CAVE_BASE" \
            "$POINTER_PAYLOAD" \
            "${POINTER_RELOC_STR_PARMS_GET_STR}:$PUDDING_STR_PARMS_GET_STR" \
            "${POINTER_RELOC_ATOI}:$PUDDING_ATOI" \
            "${POINTER_RELOC_RATE_RETURN}:$(offset_add "$PUDDING_RATE_SITE" 4)" \
            || abort "! Android 16 sampling_rate handler injection failed"
        $ELFPATCHER inject "$HAL_DEST" "$PUDDING_WORKER_CAVE" \
            "$POINTER_WORKER_PAYLOAD" \
            "${POINTER_RELOC_WORKER_STANDBY}:$PUDDING_STANDBY" \
            "${POINTER_RELOC_WORKER_RETURN}:$(offset_add "$PUDDING_WORKER_SITE" 4)" \
            || abort "! Android 16 sampling_rate worker injection failed"
        $ELFPATCHER branch "$HAL_DEST" "$PUDDING_RATE_SITE" \
            "$PUDDING_CAVE_BASE" B \
            || abort "! Android 16 sampling_rate hook relocation failed"
        $ELFPATCHER branch "$HAL_DEST" "$PUDDING_WORKER_SITE" \
            "$PUDDING_WORKER_CAVE" B \
            || abort "! Android 16 sampling_rate worker hook relocation failed"
    fi

    branch_points_to "$POLICY_DEST" "$SELECT_SITE" "$CAVE_BASE" \
        || abort "! Android 16 selectOutput verification failed"
    branch_points_to "$POLICY_DEST" "$DEFAULT_SITE" "$DEFAULT_CAVE" \
        || abort "! Android 16 HIFI default verification failed"
    branch_points_to "$FLINGER_DEST" "$MIXER_SITE" "$MIXER_TARGET" \
        || abort "! Android 16 MixerThread verification failed"
    $ELFPATCHER find "$USB_DEST" "$usb_domain" "$USB_RATE_PATCHED" \
        >/dev/null || abort "! Android 16 Qualcomm USB verification failed"

    if [ "$HAL_PATCH_KIND" = dada-worker-rate-handler ]; then
        branch_points_to "$HAL_DEST" "$DADA_RATE_SITE" \
            "$DADA_PARAMETER_CAVE" \
            || abort "! Dada sampling_rate parameter verification failed"
        branch_points_to "$HAL_DEST" "$DADA_WORKER_SITE" \
            "$DADA_WORKER_CAVE" \
            || abort "! Dada sampling_rate worker verification failed"
    elif [ "$HAL_PATCH_KIND" = a16-pointer-rate-handler ] \
            || [ "$HAL_PATCH_KIND" = a16-shifted-pointer-rate-handler ]; then
        branch_points_to "$HAL_DEST" "$PUDDING_RATE_SITE" \
            "$PUDDING_CAVE_BASE" \
            || abort "! Android 16 sampling_rate hook verification failed"
        branch_points_to "$HAL_DEST" "$PUDDING_WORKER_SITE" \
            "$PUDDING_WORKER_CAVE" \
            || abort "! Android 16 sampling_rate worker verification failed"
    fi

    USB_TABLE_SITE=$(ep_symbol "$USB_DEST" "$USB_RATE_SYMBOL" \
        'USB rate table') || abort "! Cannot resolve Android 16 USB rate table"
    ui_print "- Offline Android 16 map: policy=$SELECT_SITE cave=$CAVE_BASE"
    ui_print "- Offline Android 16 map: mixer=$MIXER_SITE USB-table=$USB_TABLE_SITE"
    if [ "$HAL_PATCH_KIND" = dada-worker-rate-handler ]; then
        ui_print "- Offline Android 16 map: Dada-HAL parameter=$DADA_RATE_SITE worker=$DADA_WORKER_SITE cave=$DADA_CAVE_BASE"
    elif [ "$HAL_PATCH_KIND" = nezha-usecase-guard ]; then
        ui_print "- Offline Android 16 map: Qualcomm-HAL=$QTI_SITE"
    else
        ui_print "- Offline Android 16 map: pointer-HAL parameter=$PUDDING_RATE_SITE worker=$PUDDING_WORKER_SITE cave=$PUDDING_CAVE_BASE"
    fi
}
