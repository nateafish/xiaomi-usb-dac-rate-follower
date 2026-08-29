#!/system/bin/sh

. "$TARGET_DIR/usecases/native-hifi-route.conf"
. "$TARGET_DIR/usecases/hifi-rate-lifecycle.conf"
. "$TARGET_DIR/usecases/hifi-dynamic-default.conf"
. "$TARGET_DIR/usecases/usb-output-arbitration.conf"
. "$TARGET_DIR/usecases/mixer-hal-sync.conf"
. "$TARGET_DIR/usecases/usb-441-rate-table.conf"
. "$TARGET_DIR/usecases/qti-hifi-reconfigure.conf"
. "$TARGET_DIR/usecases/qti-lockfree-reconfigure.conf"
. "$MODPATH/patches/a17_native_hifi_cave.relocations.conf" \
    || abort "! Missing Android 17 native HIFI relocation manifest"
. "$MODPATH/patches/a17_lockfree.relocations.conf" \
    || abort "! Missing Android 17 lock-free relocation manifest"
. "$MODPATH/lib/elf-runtime.sh"

apply_target_patches() {
    ui_print "- Resolving Android 17 use cases by semantic signatures"

    ep_find "$COMPONENTS_SOURCE" exec "$ROUTE_COMPONENT_COLLECTION_LAYOUT" \
        'SwAudioOutputCollection item layout' >/dev/null \
        || abort "! Output-collection layout is incompatible"
    ep_find "$COMPONENTS_SOURCE" exec "$ROUTE_COMPONENT_DEVICE_VECTOR_LAYOUT" \
        'AudioOutputDescriptor device-vector layout' >/dev/null \
        || abort "! Device-vector layout is incompatible"
    ep_find "$COMPONENTS_SOURCE" exec "$ROUTE_COMPONENT_DEVICE_TYPE_LAYOUT" \
        'DeviceDescriptor type layout' >/dev/null \
        || abort "! DeviceDescriptor layout is incompatible"
    ep_find "$IMPL_SOURCE" exec "$ROUTE_IMPL_PROFILE_LAYOUT" \
        'Xiaomi output-profile layout' >/dev/null \
        || abort "! Xiaomi output-profile layout is incompatible"
    ep_find "$IMPL_SOURCE" exec "$ROUTE_IMPL_NAME_LAYOUT" \
        'Xiaomi IOProfile name layout' >/dev/null \
        || abort "! Xiaomi IOProfile layout is incompatible"
    ep_find "$POLICY_DEST" exec "$ROUTE_APP_BODY_LAYOUT" \
        'unmodified HIFI package-filter body' >/dev/null \
        || abort "! HIFI package-filter body is incompatible or already modified"

    select_match=$(ep_find "$POLICY_DEST" exec "$ROUTE_SELECT_CONTEXT" \
        'native selectOutput call site') || abort "! Cannot resolve selectOutput"
    SELECT_SITE=$(offset_add "$select_match" "$ROUTE_SELECT_SITE_DELTA")
    app_match=$(ep_find "$POLICY_DEST" exec "$ROUTE_APP_CONTEXT" \
        'HIFI package-filter entry') || abort "! Cannot resolve package filter"
    APP_SITE=$(offset_add "$app_match" "$ROUTE_APP_SITE_DELTA")
    final_match=$(ep_find "$POLICY_DEST" exec "$LIFECYCLE_FINAL_CONTEXT" \
        'LATEST_MAX final-stop transition') || abort "! Cannot resolve final-stop transition"
    FINAL_SITE=$(offset_add "$final_match" "$LIFECYCLE_FINAL_SITE_DELTA")
    active_match=$(ep_find "$POLICY_DEST" exec "$LIFECYCLE_ACTIVE_CONTEXT" \
        'LATEST_MAX active-rate lookup') || abort "! Cannot resolve active-rate lookup"
    ACTIVE_SITE=$(offset_add "$active_match" "$LIFECYCLE_ACTIVE_SITE_DELTA")
    IDLE_CALLER_SITE=$(ep_find "$POLICY_DEST" exec \
        "$LIFECYCLE_IDLE_CALLER_CONTEXT" 'HIFI idle-rate caller') \
        || abort "! Cannot resolve idle-rate caller"
    IDLE_CALLER_SITE=$(offset_add "$IDLE_CALLER_SITE" \
        "$LIFECYCLE_IDLE_CALLER_SITE_DELTA")
    cave_anchor=$(ep_find "$POLICY_DEST" exec "$LIFECYCLE_CAVE_ANCHOR" \
        'native executable-cave anchor') || abort "! Cannot resolve executable cave"
    CAVE_BASE=$(offset_add "$cave_anchor" "$LIFECYCLE_CAVE_DELTA")
    SELECT_CAVE=$(offset_add "$CAVE_BASE" \
        "$A17_NATIVE_HIFI_SYMBOL_NATIVE_HIFI_SELECT_HOOK")
    APP_CAVE=$(offset_add "$CAVE_BASE" \
        "$A17_NATIVE_HIFI_SYMBOL_NATIVE_HIFI_APP_FILTER")
    ACTIVE_CAVE=$(offset_add "$CAVE_BASE" \
        "$A17_NATIVE_HIFI_SYMBOL_LATEST_MAX_IDLE_RATE")
    FINAL_CAVE=$(offset_add "$CAVE_BASE" \
        "$A17_NATIVE_HIFI_SYMBOL_LATEST_MAX_IDLE_TRANSITION")
    NATIVE_USB_HELPER=$(offset_add "$CAVE_BASE" \
        "$A17_NATIVE_HIFI_SYMBOL_NATIVE_HIFI_USB_ONLY_OUTPUT")
    IDLE_CAVE=$(offset_add "$CAVE_BASE" 788)
    GATE_CAVE=$(offset_add "$CAVE_BASE" 820)
    DEFAULT_CAVE=$(offset_add "$CAVE_BASE" 960)
    ARBITRATION_CAVE=$(offset_add "$CAVE_BASE" 1048)

    default_match=$(ep_find "$POLICY_DEST" exec "$HIFI_DEFAULT_CONTEXT" \
        'hifi_playback dynamic default') || abort "! Cannot resolve HIFI default"
    DEFAULT_SITE=$(offset_add "$default_match" "$HIFI_DEFAULT_SITE_DELTA")
    gate_match=$(ep_find "$POLICY_DEST" exec "$USB_GATE_CONTEXT" \
        'USB sampling-rate sender gate') || abort "! Cannot resolve USB sender gate"
    GATE_SITE=$(offset_add "$gate_match" "$USB_GATE_SITE_DELTA")

    VENDOR_SELECT=$(ep_plt "$POLICY_DEST" "$ROUTE_VENDOR_SELECT_PLT" \
        'Xiaomi selectOutput callback') || abort "! Cannot resolve Xiaomi callback"
    OUTPUT_IS_ACTIVE=$(ep_plt "$POLICY_DEST" "$USB_GATE_OUTPUT_ACTIVE_PLT" \
        'AudioOutputDescriptor::isActive') || abort "! Cannot resolve output activity method"
    PROFILE_ALL_STOPPED=$(ep_symbol "$POLICY_DEST" \
        "$LIFECYCLE_ALL_STOPPED_SYMBOL" 'HIFI lifecycle predicate') \
        || abort "! Cannot resolve HIFI lifecycle predicate"
    TRUE_RETURN=$(ep_find "$POLICY_DEST" "$LIFECYCLE_TRUE_RETURN_DOMAIN" \
        "$LIFECYCLE_TRUE_RETURN_PATTERN" 'LATEST_MAX true-return block') \
        || abort "! Cannot resolve LATEST_MAX return"
    ZERO_PATH=$(ep_find "$POLICY_DEST" "symbol:$USB_GATE_FUNCTION" \
        "$USB_GATE_ZERO_CONTEXT" 'sampling-rate zero path') \
        || abort "! Cannot resolve sampling-rate zero path"
    require_call_or_hook_branch "$POLICY_DEST" "$SELECT_SITE" \
        "$VENDOR_SELECT" "$SELECT_CAVE" 'selectOutput hook'
    require_stock_or_hook_branch "$POLICY_DEST" "$APP_SITE" \
        "$ROUTE_APP_STOCK" "$APP_CAVE" 'application filter'
    require_stock_or_hook_branch "$POLICY_DEST" "$FINAL_SITE" \
        "$LIFECYCLE_FINAL_STOCK" "$FINAL_CAVE" 'final-stop hook'
    require_stock_or_hook_branch "$POLICY_DEST" "$ACTIVE_SITE" \
        "$LIFECYCLE_ACTIVE_STOCK" "$ACTIVE_CAVE" 'active-rate hook'
    require_stock_or_hook_branch "$POLICY_DEST" "$IDLE_CALLER_SITE" \
        "$LIFECYCLE_IDLE_CALLER_STOCK" "$IDLE_CAVE" 'idle-rate caller'
    require_stock_or_hook_branch "$POLICY_DEST" "$DEFAULT_SITE" \
        "$HIFI_DEFAULT_STOCK" "$DEFAULT_CAVE" 'HIFI dynamic default'
    require_cbz_or_hook_branch "$POLICY_DEST" "$GATE_SITE" \
        "$ZERO_PATH" "$USB_GATE_REGISTER" "$GATE_CAVE" 'USB sender gate'

    $ELFPATCHER inject "$POLICY_DEST" "$CAVE_BASE" \
        "$MODPATH/patches/native_hifi_cave.template.bin" \
        "${A17_NATIVE_HIFI_VENDOR_SELECT_OUTPUT_STUB}:$VENDOR_SELECT" \
        "${A17_NATIVE_HIFI_SELECT_OUTPUT_RETURN}:$(offset_add "$SELECT_SITE" 4)" \
        "${A17_NATIVE_HIFI_HIFI_APP_STOCK_CONTINUE}:$(offset_add "$APP_SITE" 4)" \
        "${A17_NATIVE_HIFI_LATEST_MAX_RATE_EMPTY_RETURN}:$(offset_add "$ACTIVE_SITE" 52)" \
        "${A17_NATIVE_HIFI_LATEST_MAX_RATE_CONTINUE}:$(offset_add "$ACTIVE_SITE" 4)" \
        "${A17_NATIVE_HIFI_LATEST_MAX_TRUE_RETURN}:$TRUE_RETURN" \
        || abort "! Native HIFI payload injection failed"
    $ELFPATCHER inject "$POLICY_DEST" "$IDLE_CAVE" \
        "$MODPATH/patches/hifi_idle_rate_cave.template.bin" \
        "4:COND19:$(offset_add "$IDLE_CALLER_SITE" 8)" \
        "8:CB19:$(offset_add "$IDLE_CALLER_SITE" 24)" \
        "16:BL:$PROFILE_ALL_STOPPED" \
        "20:CB19:$(offset_add "$IDLE_CALLER_SITE" 24)" \
        "28:B:$(offset_add "$IDLE_CALLER_SITE" 88)" \
        || abort "! HIFI idle-rate payload injection failed"
    $ELFPATCHER inject "$POLICY_DEST" "$GATE_CAVE" \
        "$MODPATH/patches/usb_output_gate_cave.template.bin" \
        "0:B:$ARBITRATION_CAVE" \
        || abort "! USB gate trampoline injection failed"
    $ELFPATCHER inject "$POLICY_DEST" "$ARBITRATION_CAVE" \
        "$MODPATH/patches/usb_output_arbitration_cave.template.bin" \
        "104:BL:$NATIVE_USB_HELPER" \
        "152:BL:$OUTPUT_IS_ACTIVE" \
        "164:BL:$NATIVE_USB_HELPER" \
        "228:B:$(offset_add "$GATE_SITE" 4)" \
        "252:B:$ZERO_PATH" \
        || abort "! USB arbitration payload injection failed"
    $ELFPATCHER inject "$POLICY_DEST" "$DEFAULT_CAVE" \
        "$MODPATH/patches/hifi_dynamic_default_cave.template.bin" \
        "68:B:$(offset_add "$DEFAULT_SITE" 4)" \
        || abort "! HIFI default-rate payload injection failed"

    $ELFPATCHER branch "$POLICY_DEST" "$SELECT_SITE" "$SELECT_CAVE" B \
        || abort "! selectOutput branch relocation failed"
    $ELFPATCHER branch "$POLICY_DEST" "$APP_SITE" "$APP_CAVE" B \
        || abort "! HIFI package-filter branch relocation failed"
    $ELFPATCHER branch "$POLICY_DEST" "$FINAL_SITE" "$FINAL_CAVE" B \
        || abort "! final-stop branch relocation failed"
    $ELFPATCHER branch "$POLICY_DEST" "$ACTIVE_SITE" "$ACTIVE_CAVE" B \
        || abort "! active-rate branch relocation failed"
    $ELFPATCHER branch "$POLICY_DEST" "$IDLE_CALLER_SITE" "$IDLE_CAVE" B \
        || abort "! idle-rate caller relocation failed"
    $ELFPATCHER branch "$POLICY_DEST" "$GATE_SITE" "$GATE_CAVE" B \
        || abort "! USB sender-gate relocation failed"
    $ELFPATCHER branch "$POLICY_DEST" "$DEFAULT_SITE" "$DEFAULT_CAVE" B \
        || abort "! HIFI default-rate relocation failed"

    mixer_match=$(ep_find "$FLINGER_DEST" exec "$MIXER_SYNC_CONTEXT" \
        'MixerThread HAL synchronization branch') || abort "! Cannot resolve MixerThread branch"
    MIXER_SITE=$(offset_add "$mixer_match" "$MIXER_SYNC_SITE_DELTA")
    mixer_word=$($ELFPATCHER word "$FLINGER_DEST" "$MIXER_SITE") \
        || abort "! Cannot read MixerThread branch"
    MIXER_TARGET=$(branch_target "$FLINGER_DEST" "$MIXER_SITE") \
        || abort "! MixerThread synchronization target is not a branch"
    if [ $(( mixer_word & 0xff00001f )) -ne $(( 0x54000008 )) ] \
            && [ $(( mixer_word & 0xfc000000 )) -ne $(( 0x14000000 )) ]; then
        abort "! Unknown MixerThread branch state"
    fi
    $ELFPATCHER branch "$FLINGER_DEST" "$MIXER_SITE" "$MIXER_TARGET" B \
        || abort "! MixerThread branch relocation failed"

    usb_domain="symbol:$USB_RATE_SYMBOL"
    if $ELFPATCHER find "$USB_DEST" "$usb_domain" "$USB_RATE_PATCHED" \
            >/dev/null 2>&1; then
        :
    elif $ELFPATCHER find "$USB_DEST" "$usb_domain" "$USB_RATE_STOCK" \
            >/dev/null 2>&1; then
        $ELFPATCHER replace "$USB_DEST" "$usb_domain" "$USB_RATE_STOCK" 0 \
            "$USB_RATE_PATCHED" >/dev/null \
            || abort "! Qualcomm USB rate-table replacement failed"
    else
        abort "! Qualcomm USB rate table is unknown or ambiguous"
    fi

    parameter_match=$(ep_find "$HAL_DEST" exec \
        "$QTI_LOCKFREE_PARAMETER_CONTEXT" \
        'Qualcomm sampling-rate parameter handoff') \
        || abort "! Cannot resolve Qualcomm parameter handoff"
    QTI_PARAMETER_SITE=$(offset_add "$parameter_match" \
        "$QTI_LOCKFREE_PARAMETER_SITE_DELTA")
    QTI_PARAMETER_STOCK_RESUME=$(offset_add "$QTI_PARAMETER_SITE" \
        "$QTI_LOCKFREE_PARAMETER_STOCK_RESUME_DELTA")
    QTI_PARAMETER_SKIP=$(offset_add "$QTI_PARAMETER_SITE" \
        "$QTI_LOCKFREE_PARAMETER_SKIP_DELTA")
    branch_points_to "$HAL_DEST" \
        "$(offset_add "$QTI_PARAMETER_SITE" \
            "$QTI_LOCKFREE_PARAMETER_EQUAL_BRANCH_DELTA")" \
        "$QTI_PARAMETER_SKIP" \
        || abort "! Qualcomm parameter equal-rate target changed"

    transfer_match=$(ep_find "$HAL_DEST" exec \
        "$QTI_LOCKFREE_TRANSFER_CONTEXT" \
        'Qualcomm transfer synchronization block') \
        || abort "! Cannot resolve Qualcomm transfer synchronization"
    QTI_TRANSFER_SITE=$(offset_add "$transfer_match" \
        "$QTI_LOCKFREE_TRANSFER_SITE_DELTA")
    QTI_TRANSFER_LOCK=$(offset_add "$QTI_TRANSFER_SITE" \
        "$QTI_LOCKFREE_TRANSFER_LOCK_DELTA")
    QTI_TRANSFER_SKIP=$(offset_add "$QTI_TRANSFER_SITE" \
        "$QTI_LOCKFREE_TRANSFER_SKIP_DELTA")
    branch_points_to "$HAL_DEST" \
        "$(offset_add "$QTI_TRANSFER_SITE" 4)" "$QTI_TRANSFER_LOCK" \
        || abort "! Qualcomm stock transfer lock entry changed"
    branch_points_to "$HAL_DEST" \
        "$(offset_add "$QTI_TRANSFER_SITE" 12)" "$QTI_TRANSFER_SKIP" \
        || abort "! Qualcomm stock transfer skip target changed"

    QTI_CFI_CHECK=$(ep_symbol "$HAL_DEST" "$QTI_LOCKFREE_CFI_SYMBOL" \
        'Qualcomm CFI boundary') || abort "! Cannot resolve Qualcomm CFI boundary"
    QTI_LOCKFREE_CAVE=$(offset_add "$QTI_CFI_CHECK" \
        "$QTI_LOCKFREE_CAVE_DELTA")
    QTI_PARAMETER_CAVE=$(offset_add "$QTI_LOCKFREE_CAVE" \
        "$A17_LOCKFREE_SYMBOL_A17_LOCKFREE_PARAMETER_HOOK")
    QTI_TRANSFER_CAVE=$(offset_add "$QTI_LOCKFREE_CAVE" \
        "$A17_LOCKFREE_SYMBOL_A17_LOCKFREE_TRANSFER_HOOK")
    QTI_ATOI=$(ep_plt "$HAL_DEST" atoi 'Qualcomm atoi') \
        || abort "! Cannot resolve Qualcomm atoi"
    QTI_STANDBY=$(ep_symbol "$HAL_DEST" \
        "$QTI_LOCKFREE_STANDBY_SYMBOL" 'Xiaomi stream standby') \
        || abort "! Cannot resolve Xiaomi stream standby"

    $ELFPATCHER inject "$HAL_DEST" "$QTI_LOCKFREE_CAVE" \
        "$MODPATH/patches/a17_lockfree.template.bin" \
        "${A17_LOCKFREE_A17_PARAMETER_STOCK_RESUME}:$QTI_PARAMETER_STOCK_RESUME" \
        "${A17_LOCKFREE_ATOI}:$QTI_ATOI" \
        "${A17_LOCKFREE_A17_PARAMETER_SKIP_STANDBY}:$QTI_PARAMETER_SKIP" \
        "${A17_LOCKFREE_A17_TRANSFER_LOCK_ENTRY}:$QTI_TRANSFER_LOCK" \
        "${A17_LOCKFREE_A17_WORKER_STANDBY}:$QTI_STANDBY" \
        "${A17_LOCKFREE_A17_TRANSFER_SKIP_LOCK}:$QTI_TRANSFER_SKIP" \
        || abort "! Qualcomm lock-free cave injection failed"

    if hex_at "$HAL_DEST" "$QTI_PARAMETER_SITE" \
            "$QTI_LOCKFREE_PARAMETER_STOCK"; then
        $ELFPATCHER branch "$HAL_DEST" "$QTI_PARAMETER_SITE" \
            "$QTI_PARAMETER_CAVE" B \
            || abort "! Qualcomm parameter handoff branch failed"
    else
        branch_points_to "$HAL_DEST" "$QTI_PARAMETER_SITE" \
            "$QTI_PARAMETER_CAVE" \
            || abort "! Unknown Qualcomm parameter handoff state"
    fi
    if hex_at "$HAL_DEST" "$QTI_TRANSFER_SITE" \
            "$QTI_LOCKFREE_TRANSFER_FIRST"; then
        $ELFPATCHER branch "$HAL_DEST" "$QTI_TRANSFER_SITE" \
            "$QTI_TRANSFER_CAVE" B \
            || abort "! Qualcomm transfer handoff branch failed"
    else
        branch_points_to "$HAL_DEST" "$QTI_TRANSFER_SITE" \
            "$QTI_TRANSFER_CAVE" \
            || abort "! Unknown Qualcomm transfer handoff state"
    fi

    frame_entry=$(ep_find "$HAL_DEST" exec "$QTI_FRAME_ENTRY" \
        'Qualcomm HIFI frame-count function') || abort "! Cannot resolve HIFI frame-count function"
    FRAME_BODY=$(offset_add "$frame_entry" "$QTI_FRAME_BODY_DELTA")
    if hex_at "$HAL_DEST" "$FRAME_BODY" "$QTI_FRAME_STOCK"; then
        :
    elif hex_at "$HAL_DEST" "$FRAME_BODY" "$QTI_FRAME_LEGACY"; then
        $ELFPATCHER replace "$HAL_DEST" "range:$FRAME_BODY:24" \
            "$QTI_FRAME_LEGACY" 0 "$QTI_FRAME_STOCK" >/dev/null \
            || abort "! Qualcomm stock frame-count restoration failed"
    else
        abort "! Unknown Qualcomm HIFI frame-count state"
    fi

    branch_points_to "$POLICY_DEST" "$SELECT_SITE" "$CAVE_BASE" \
        || abort "! selectOutput hook verification failed"
    branch_points_to "$POLICY_DEST" "$GATE_SITE" "$GATE_CAVE" \
        || abort "! USB sender-gate verification failed"
    branch_points_to "$FLINGER_DEST" "$MIXER_SITE" "$MIXER_TARGET" \
        || abort "! MixerThread synchronization verification failed"
    $ELFPATCHER find "$USB_DEST" "$usb_domain" "$USB_RATE_PATCHED" \
        >/dev/null || abort "! Qualcomm USB table verification failed"
    branch_points_to "$HAL_DEST" "$QTI_PARAMETER_SITE" \
        "$QTI_PARAMETER_CAVE" \
        || abort "! Qualcomm parameter handoff verification failed"
    branch_points_to "$HAL_DEST" "$QTI_TRANSFER_SITE" \
        "$QTI_TRANSFER_CAVE" \
        || abort "! Qualcomm transfer handoff verification failed"
    hex_at "$HAL_DEST" "$FRAME_BODY" "$QTI_FRAME_STOCK" \
        || abort "! Qualcomm frame-count verification failed"

    USB_TABLE_SITE=$(ep_symbol "$USB_DEST" "$USB_RATE_SYMBOL" \
        'USB rate table') || abort "! Cannot resolve Qualcomm USB rate table"
    ui_print "- Dynamic patch map: policy=$SELECT_SITE cave=$CAVE_BASE"
    ui_print "- Dynamic patch map: mixer=$MIXER_SITE USB-table=$USB_TABLE_SITE"
    ui_print "- Dynamic patch map: Qualcomm-HAL parameter=$QTI_PARAMETER_SITE transfer=$QTI_TRANSFER_SITE cave=$QTI_LOCKFREE_CAVE"
}
