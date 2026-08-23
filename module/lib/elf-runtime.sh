#!/system/bin/sh

ep_find() {
    ep_file=$1
    ep_domain=$2
    ep_pattern=$3
    ep_label=$4
    if ! ep_result=$($ELFPATCHER find "$ep_file" "$ep_domain" "$ep_pattern" 2>&1); then
        ui_print "! $ep_label: $ep_result" >&2
        return 1
    fi
    echo "$ep_result"
}

ep_symbol() {
    ep_file=$1
    ep_name=$2
    ep_label=$3
    if ! ep_result=$($ELFPATCHER symbol "$ep_file" "$ep_name" 2>&1); then
        ui_print "! $ep_label: $ep_result" >&2
        return 1
    fi
    echo "$ep_result"
}

ep_plt() {
    ep_file=$1
    ep_name=$2
    ep_label=$3
    if ! ep_result=$($ELFPATCHER plt "$ep_file" "$ep_name" 2>&1); then
        ui_print "! $ep_label: $ep_result" >&2
        return 1
    fi
    echo "$ep_result"
}

offset_add() {
    echo $(( $1 + $2 ))
}

hex_at() {
    hex_file=$1
    hex_offset=$2
    hex_expected=$3
    hex_size=$(( ${#hex_expected} / 2 ))
    $ELFPATCHER find "$hex_file" "range:$hex_offset:$hex_size" \
        "$hex_expected" >/dev/null 2>&1
}

branch_target() {
    $ELFPATCHER branch-target "$1" "$2" 2>/dev/null
}

branch_points_to() {
    actual_target=$(branch_target "$1" "$2") || return 1
    [ $(( actual_target )) -eq $(( $3 )) ]
}

require_stock_or_hook_branch() {
    branch_file=$1
    branch_site=$2
    branch_stock=$3
    branch_hook=$4
    branch_label=$5
    if hex_at "$branch_file" "$branch_site" "$branch_stock" \
            || branch_points_to "$branch_file" "$branch_site" "$branch_hook"; then
        return 0
    fi
    abort "! Unknown or mixed branch state: $branch_label"
}

require_call_or_hook_branch() {
    branch_file=$1
    branch_site=$2
    branch_stock_target=$3
    branch_hook=$4
    branch_label=$5
    if branch_points_to "$branch_file" "$branch_site" "$branch_stock_target" \
            || branch_points_to "$branch_file" "$branch_site" "$branch_hook"; then
        return 0
    fi
    abort "! Unknown or mixed call state: $branch_label"
}

require_cbz_or_hook_branch() {
    branch_file=$1
    branch_site=$2
    branch_stock_target=$3
    branch_register=$4
    branch_hook=$5
    branch_label=$6
    branch_word=$($ELFPATCHER word "$branch_file" "$branch_site") \
        || abort "! Cannot read branch instruction: $branch_label"
    if [ $(( branch_word & 0x7f00001f )) -eq \
            $(( 0x34000000 | branch_register )) ] \
            && branch_points_to "$branch_file" "$branch_site" \
                "$branch_stock_target"; then
        return 0
    fi
    branch_points_to "$branch_file" "$branch_site" "$branch_hook" \
        && return 0
    abort "! Unknown or mixed CBZ state: $branch_label"
}
