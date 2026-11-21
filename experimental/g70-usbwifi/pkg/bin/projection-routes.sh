# SPDX-License-Identifier: AGPL-3.0-only
# Scope is the confirmed AP subnet, in the two Android policy tables used by
# the supplied USB-Wi-Fi reference. Add only a missing prefix; never replace
# an existing route. Ownership records permit exact, current-boot cleanup.
PROJECTION_PREFIX=192.168.43.0/24
route_prefix_line() {
    _rq=$(ip route show table "$1" 2>/dev/null) || return 1
    echo "$_rq" | bb awk -v p="$PROJECTION_PREFIX" '$1 == p || ($2 == p && $1 ~ /^(unicast|local|throw|unreachable|blackhole|prohibit)$/)'
}
route_is_wlan() {
    echo "$1" | bb awk 'NF {n++; for(i=1;i<NF;i++) if($i=="dev" && $(i+1)=="wlan0") w++} END {exit !(n==1 && w==1)}'
}
route_state() {
    if [ "$(value "$BK/route-$1.state")" != "$2" ]; then
        echo "$2" > "$BK/route-$1.state"
        event "projection_route_table_$1_$2"
    fi
}
projection_routes_off() {
    for _rt in 60 61; do
        _rb=; _ri=
        { read -r _rb _ri < "$BK/route-$_rt.owner"; } 2>/dev/null || continue
        if [ "$_rb" = "$(boot_id)" ] && our_wlan && [ "$_ri" = "$(value "$NET/wlan0/ifindex")" ]; then
            _present=$(route_prefix_line "$_rt") || { route_state "$_rt" cleanup_query_failed; continue; }
            if [ -n "$_present" ] && [ "$_present" = "$(value "$BK/route-$_rt.line")" ]; then
                ip route del "$PROJECTION_PREFIX" dev wlan0 table "$_rt" >/dev/null 2>&1 || {
                    route_state "$_rt" cleanup_failed; continue;
                }
                route_state "$_rt" removed
            fi
        fi
        rm -f "$BK/route-$_rt.owner" "$BK/route-$_rt.line"
    done
    return 0
}
ensure_projection_route() {
    _rt=$1
    _present=$(route_prefix_line "$_rt") || { route_state "$_rt" query_failed; return 0; }
    if [ -n "$_present" ]; then
        if route_is_wlan "$_present"; then route_state "$_rt" wlan0_present
        else route_state "$_rt" existing_route_preserved; fi
        return 0
    fi
    # A matching prefix may have been removed by netd or a USB generation
    # change. An empty result is required before every add.
    if ! ip route add "$PROJECTION_PREFIX" dev wlan0 table "$_rt" >/dev/null 2>&1; then
        route_state "$_rt" add_failed
        return 0
    fi
    _added=$(route_prefix_line "$_rt")
    if [ -z "$_added" ] || ! route_is_wlan "$_added"; then
        ip route del "$PROJECTION_PREFIX" dev wlan0 table "$_rt" >/dev/null 2>&1
        route_state "$_rt" add_unconfirmed
        return 0
    fi
    echo "$_added" > "$BK/route-$_rt.line" &&
        echo "$(boot_id) $(value "$NET/wlan0/ifindex")" > "$BK/route-$_rt.owner" || {
        ip route del "$PROJECTION_PREFIX" dev wlan0 table "$_rt" >/dev/null 2>&1
        rm -f "$BK/route-$_rt.owner" "$BK/route-$_rt.line"
        route_state "$_rt" ownership_record_failed
        return 0
    }
    route_state "$_rt" added
}
projection_routes_tick() {
    if ! our_wlan || ! ap_has_ip || [ -z "$(kp_host_pids)" ] ||
        [ -z "$(kp_dhcp_pid)" ] || [ -f "$BK/maintenance" ] || other_host_on ||
        [ ! -f "$R/data/hmgapi/mods/wireless-carplay-aa/mod.json" ] ||
        [ "$(getprop persist.sys.iap2.wifi 2>/dev/null)" != t ] ||
        [ -f "$R/data/hmgapi/mods/wireless-carplay-aa/.disabled" ]; then
        projection_routes_off
        return 0
    fi
    for _rt in 60 61; do ensure_projection_route "$_rt"; done
}
projection_route_diagnostics() {
    for _dt in main 60 61; do
        _dr=$(route_prefix_line "$_dt")
        _rr=$?
        if [ "$_rr" != 0 ]; then _class=unavailable
        elif [ -z "$_dr" ]; then _class=absent
        elif route_is_wlan "$_dr"; then _class=wlan0
        else _class=other_or_multiple; fi
        echo "projection_route_table_${_dt}=$_class"
    done
}
