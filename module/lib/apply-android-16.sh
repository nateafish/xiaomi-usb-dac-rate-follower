#!/system/bin/sh

. "$TARGET_DIR/usecases/native-hifi-route.conf"
. "$TARGET_DIR/usecases/hifi-dynamic-default.conf"
. "$TARGET_DIR/usecases/mixer-hal-sync.conf"
. "$TARGET_DIR/usecases/usb-441-rate-table.conf"
. "$TARGET_DIR/usecases/qti-hifi-reconfigure.conf"
. "$TARGET_DIR/usecases/pudding-sampling-rate-handler.conf"
. "$MODPATH/patches/a16_native_hifi_route.relocations.conf" \
    || abort "! Missing Android 16 native HIFI relocation manifest"
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
    if qti_match=$($ELFPATCHER find "$HAL_DEST" exec \
            "$QTI_RECONFIG_CONTEXT" 2>/dev/null); then
        qti_state=stock
        HAL_PATCH_KIND=nezha-usecase-guard
    elif qti_match=$($ELFPATCHER find "$HAL_DEST" exec \
            "$QTI_RECONFIG_PATCHED_CONTEXT" 2>/dev/null); then
        qti_state=patched
        HAL_PATCH_KIND=nezha-usecase-guard
    elif pudding_match=$($ELFPATCHER find "$HAL_DEST" \
            "symbol:$PUDDING_RATE_FUNCTION" \
            "$PUDDING_RATE_CONTEXT" 2>/dev/null); then
        HAL_PATCH_KIND=pudding-rate-handler
    else
        abort "! Android 16 Qualcomm HAL is neither a supported Nezha nor Pudding layout"
    fi

    if [ "$HAL_PATCH_KIND" = nezha-usecase-guard ]; then
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
        ep_find "$HAL_DEST" "symbol:$PUDDING_RATE_FUNCTION" \
            "$PUDDING_PLATFORM_CONFIG_LAYOUT" \
            'Pudding Platform/AudioPortConfig pointer layout' >/dev/null \
            || abort "! Pudding Platform/AudioPortConfig layout is incompatible"
        ep_find "$HAL_DEST" "symbol:$PUDDING_RATE_FUNCTION" \
            "$PUDDING_CACHED_ATTR_LAYOUT" \
            'Pudding cached PAL-attribute layout' >/dev/null \
            || abort "! Pudding cached PAL-attribute layout is incompatible"
        ep_find "$HAL_DEST" "symbol:$PUDDING_CONFIGURE_FUNCTION" \
            "$PUDDING_CONFIG_MUTEX_LAYOUT" \
            'Pudding configure-mutex layout' >/dev/null \
            || abort "! Pudding configure mutex is incompatible"
        ep_find "$HAL_DEST" "symbol:$PUDDING_CONFIGURE_FUNCTION" \
            "$PUDDING_SAMPLE_RATE_LAYOUT" \
            'Pudding AudioPortConfig sample-rate layout' >/dev/null \
            || abort "! Pudding sample-rate field is incompatible"
        ep_find "$HAL_DEST" "symbol:$PUDDING_STANDBY_SYMBOL" \
            "$PUDDING_USECASE_TAG_LAYOUT" \
            'Pudding usecase-tag layout' >/dev/null \
            || abort "! Pudding usecase tag is incompatible"
        ep_find "$HAL_DEST" \
            'symbol:_ZN3qti5audio4core16StreamOutPrimary7standbyEv' \
            "$PUDDING_PAL_HANDLE_LAYOUT" \
            'Pudding PAL-handle layout' >/dev/null \
            || abort "! Pudding PAL handle is incompatible"

        PUDDING_RATE_SITE=$(offset_add "$pudding_match" \
            "$PUDDING_RATE_SITE_DELTA")
        pudding_cave_anchor=$(ep_find "$HAL_DEST" exec \
            "$PUDDING_CAVE_ANCHOR" 'Pudding linker-gap owner') \
            || abort "! Cannot resolve the Pudding executable-gap owner"
        PUDDING_CAVE_BASE=$(offset_add "$pudding_cave_anchor" \
            "$PUDDING_CAVE_ANCHOR_SIZE")
        PUDDING_CAVE_OWNER=$(ep_plt "$HAL_DEST" \
            "$PUDDING_CAVE_OWNER_PLT" 'Pudding linker-gap owner call') \
            || abort "! Cannot resolve the Pudding linker-gap owner call"
        branch_points_to "$HAL_DEST" \
            "$(offset_add "$pudding_cave_anchor" \
                "$PUDDING_CAVE_OWNER_CALL_DELTA")" "$PUDDING_CAVE_OWNER" \
            || abort "! Pudding executable gap is not owned by the expected function"
        require_stock_or_hook_branch "$HAL_DEST" "$PUDDING_RATE_SITE" \
            "$PUDDING_RATE_STOCK" "$PUDDING_CAVE_BASE" \
            'Pudding sampling_rate hook'
        if hex_at "$HAL_DEST" "$PUDDING_RATE_SITE" \
                "$PUDDING_RATE_STOCK"; then
            resolved_pudding_cave=$(ep_cave_after "$HAL_DEST" \
                "$pudding_cave_anchor" "$PUDDING_CAVE_ANCHOR_SIZE" \
                "$PUDDING_CAVE_REQUIRED_SIZE" "$PUDDING_CAVE_ALIGNMENT" \
                'Pudding sampling_rate executable cave') \
                || abort "! Cannot allocate the Pudding sampling_rate cave"
            [ $(( resolved_pudding_cave )) -eq \
                    $(( PUDDING_CAVE_BASE )) ] \
                || abort "! Pudding linker-gap geometry changed unexpectedly"
        fi

        PUDDING_STR_PARMS_GET_STR=$(ep_plt "$HAL_DEST" \
            "$PUDDING_STR_PARMS_GET_STR_PLT" 'Pudding str_parms_get_str') \
            || abort "! Cannot resolve Pudding str_parms_get_str"
        PUDDING_ATOI=$(ep_plt "$HAL_DEST" "$PUDDING_ATOI_PLT" \
            'Pudding atoi') || abort "! Cannot resolve Pudding atoi"
        PUDDING_MUTEX_LOCK=$(ep_plt "$HAL_DEST" \
            "$PUDDING_MUTEX_LOCK_PLT" 'Pudding mutex lock') \
            || abort "! Cannot resolve Pudding mutex lock"
        PUDDING_MUTEX_UNLOCK=$(ep_plt "$HAL_DEST" \
            "$PUDDING_MUTEX_UNLOCK_PLT" 'Pudding mutex unlock') \
            || abort "! Cannot resolve Pudding mutex unlock"
        PUDDING_STANDBY=$(ep_symbol "$HAL_DEST" \
            "$PUDDING_STANDBY_SYMBOL" 'Pudding standby') \
            || abort "! Cannot resolve Pudding standby"

        $ELFPATCHER inject "$HAL_DEST" "$PUDDING_CAVE_BASE" \
            "$MODPATH/patches/a16_pudding_sampling_rate_handler.template.bin" \
            "16:BL:$PUDDING_STR_PARMS_GET_STR" \
            "28:BL:$PUDDING_ATOI" \
            "164:BL:$PUDDING_MUTEX_LOCK" \
            "172:BL:$PUDDING_STANDBY" \
            "180:BL:$PUDDING_MUTEX_UNLOCK" \
            "188:B:$(offset_add "$PUDDING_RATE_SITE" 4)" \
            || abort "! Pudding sampling_rate handler injection failed"
        $ELFPATCHER branch "$HAL_DEST" "$PUDDING_RATE_SITE" \
            "$PUDDING_CAVE_BASE" B \
            || abort "! Pudding sampling_rate hook relocation failed"
    fi

    branch_points_to "$POLICY_DEST" "$SELECT_SITE" "$CAVE_BASE" \
        || abort "! Android 16 selectOutput verification failed"
    branch_points_to "$POLICY_DEST" "$DEFAULT_SITE" "$DEFAULT_CAVE" \
        || abort "! Android 16 HIFI default verification failed"
    branch_points_to "$FLINGER_DEST" "$MIXER_SITE" "$MIXER_TARGET" \
        || abort "! Android 16 MixerThread verification failed"
    $ELFPATCHER find "$USB_DEST" "$usb_domain" "$USB_RATE_PATCHED" \
        >/dev/null || abort "! Android 16 Qualcomm USB verification failed"

    if [ "$HAL_PATCH_KIND" = pudding-rate-handler ]; then
        branch_points_to "$HAL_DEST" "$PUDDING_RATE_SITE" \
            "$PUDDING_CAVE_BASE" \
            || abort "! Pudding sampling_rate hook verification failed"
    fi

    USB_TABLE_SITE=$(ep_symbol "$USB_DEST" "$USB_RATE_SYMBOL" \
        'USB rate table') || abort "! Cannot resolve Android 16 USB rate table"
    ui_print "- Offline Android 16 map: policy=$SELECT_SITE cave=$CAVE_BASE"
    ui_print "- Offline Android 16 map: mixer=$MIXER_SITE USB-table=$USB_TABLE_SITE"
    if [ "$HAL_PATCH_KIND" = nezha-usecase-guard ]; then
        ui_print "- Offline Android 16 map: Qualcomm-HAL=$QTI_SITE"
    else
        ui_print "- Offline Android 16 map: Pudding-HAL=$PUDDING_RATE_SITE cave=$PUDDING_CAVE_BASE"
    fi
}
