# SPDX-License-Identifier: AGPL-3.0-only
# KP owns the AP configuration and wireless-mode setup. This watchdog only
# retires KP processes bound to a removed interface and supplies the DHCP
# invocation that was verified on this G70 in the 0.4.0 AP test.
KPW="$R/data/local/tmp/korea.projection"
APCONF="$R/data/misc/wifi/hostapd-kp.conf"
DHCPT="$APP/dhcp-runtime"
BR_BB=
for _ab in "$KP/bin/busybox" "$R/system/bin/busybox"; do
    [ ! -x "$_ab" ] || { BR_BB=$_ab; break; }
done
bb() { [ -n "$BR_BB" ] && "$BR_BB" "$@"; }
boot_id() { value "$PROC/sys/kernel/random/boot_id"; }
up_seconds() {
    _us=; [ ! -r "$PROC/uptime" ] || read -r _us _rest < "$PROC/uptime"
    _us=${_us%%.*}
    case "$_us" in ''|*[!0-9]*) return 1 ;; *) echo "$_us" ;; esac
}
proc_is() {
    case "$1" in ''|*[!0-9]*|0|1) return 1 ;; esac
    _pi=; _pc=; _ps=
    { read -r _pi _pc _ps _rest < "$PROC/$1/stat"; } 2>/dev/null || return 1
    [ "$_pc" = "($2)" ] && [ "$_ps" != Z ]
}
proc_arg() {
    [ -r "$PROC/$1/cmdline" ] || return 1
    bb tr '\000' '\n' < "$PROC/$1/cmdline" | bb grep -Fqx -- "$2"
}
kp_host_pids() {
    for _hp in "$PROC"/[0-9]*; do
        _hp=${_hp##*/}
        proc_is "$_hp" hostapd && proc_arg "$_hp" "$APCONF" && echo "$_hp"
    done
    return 0
}
other_host_on() {
    for _oh in "$PROC"/[0-9]*; do
        _oh=${_oh##*/}
        proc_is "$_oh" hostapd || continue
        proc_arg "$_oh" "$APCONF" || return 0
    done
    return 1
}
dhcp_record_pid() {
    _dp=; _db=
    { read -r _dp _db < "$1"; } 2>/dev/null || return 1
    [ "$_db" = "$(boot_id)" ] && proc_is "$_dp" dnsmasq &&
        proc_arg "$_dp" --interface=wlan0 &&
        proc_arg "$_dp" --dhcp-range=192.168.43.10,192.168.43.50,255.255.255.0,1h || return 1
    echo "$_dp"
}
kp_dhcp_pid() { dhcp_record_pid "$KPW/dnsmasq.pid"; }
owned_dhcp_pid() {
    _op=$(dhcp_record_pid "$BK/bridge-dhcp.pid") || return 1
    proc_arg "$_op" "--dhcp-leasefile=$DHCPT/leases" || return 1
    echo "$_op"
}
stop_owned_dhcp() {
    _sp=$(owned_dhcp_pid)
    if [ -n "$_sp" ]; then
        kill "$_sp" 2>/dev/null
        _shared=$(kp_dhcp_pid)
        [ "$_shared" != "$_sp" ] || rm -f "$KPW/dnsmasq.pid"
        rm -f "$BK/bridge-dhcp.pid"
        event bridge_dhcp_stopped
    fi
    dhcp_nat_off
}
retire_kp_ap() {
    # Both process identity and the exact config/interface arguments must match.
    # Never kill netd's hostapd/dnsmasq or an unrelated reused PID.
    for _rp in $(kp_host_pids); do kill "$_rp" 2>/dev/null; done
    _rd=$(kp_dhcp_pid)
    if [ -n "$_rd" ]; then
        kill "$_rd" 2>/dev/null
        [ "$(kp_dhcp_pid)" != "$_rd" ] || rm -f "$KPW/dnsmasq.pid"
    fi
    stop_owned_dhcp
    event stale_kp_ap_retired
    DHCP_MISSING_AT=; DHCP_TRIED_AT=
}
interface_generation() {
    _gb=; _gi=
    { read -r _gb _gi < "$BK/interface-generation"; } 2>/dev/null
    _nowboot=$(boot_id)
    if our_wlan; then
        _newindex=$(value "$NET/wlan0/ifindex")
        case "$_newindex" in ''|*[!0-9]*) return 1 ;; esac
        if [ "$_gb" = "$_nowboot" ] && [ "$_gi" != missing ] && [ "$_gi" != "$_newindex" ]; then
            record_projection_snapshot interface-replaced
            retire_kp_ap
            projection_routes_off
            event wlan0_generation_changed
        fi
        if [ "$_gb:$_gi" != "$_nowboot:$_newindex" ]; then
            echo "$_nowboot $_newindex" > "$BK/interface-generation"
        fi
    elif [ "$_gb" = "$_nowboot" ] && [ "$_gi" != missing ]; then
        record_projection_snapshot interface-loss
        retire_kp_ap
        projection_routes_off
        echo "$_nowboot missing" > "$BK/interface-generation"
        event wlan0_removed
    fi
}
ap_has_ip() {
    [ "$(bb ifconfig wlan0 2>/dev/null | bb awk '/inet addr:/ {sub(/.*inet addr:/, ""); sub(/ .*/, ""); print; exit}')" = 192.168.43.1 ]
}
prepare_dhcp() {
    mkdir -p "$DHCPT" || return 1
    chown 1000:1010 "$DHCPT" && chmod 770 "$DHCPT" || return 1
    if [ ! -p "$DHCPT/stdin" ]; then
        rm -f "$DHCPT/stdin"
        bb mkfifo "$DHCPT/stdin" || return 1
    fi
    touch "$DHCPT/leases" || return 1
    chown 1000:1010 "$DHCPT/stdin" "$DHCPT/leases" &&
        chmod 660 "$DHCPT/stdin" "$DHCPT/leases"
}
dhcp_error() {
    _de=none
    if [ -r "$BK/dhcp.raw" ]; then
        while IFS= read -r _line; do
            case "$_line" in
                *'Address already in use'*) _de=address_in_use ;;
                *'Permission denied'*) _de=permission ;;
                *'No such file or directory'*) _de=missing_path ;;
                *'unknown user'*|*'unknown group'*) _de=unknown_user_or_group ;;
                *'bad command line'*|*'unrecognized option'*|*'invalid option'*) _de=option ;;
                *'failed to start'*) [ "$_de" != none ] || _de=start_failed ;;
            esac
        done < "$BK/dhcp.raw"
    fi
    echo "$_de"
}
dhcp_stage() {
    _stage=unknown
    if [ -r "$BK/dhcp.raw" ]; then
        while IFS= read -r _line; do
            case "$_line" in
                *'bind DHCP server socket'*) _stage=dhcp_bind ;;
                *'create listening socket'*|*'bind server socket'*) _stage=dns_bind ;;
                *'netlink socket'*) _stage=netlink ;;
                *'pidfile'*) _stage=pidfile ;;
                *'lease file'*|*'leasefile'*) _stage=leasefile ;;
            esac
        done < "$BK/dhcp.raw"
    fi
    echo "$_stage"
}
launch_bridge_dhcp() {
    _launch_port=$1
    set --
    # Older Android dnsmasq requires an argument for --dhcp-broadcast.
    # Keep the tested default reply behavior and set only the two port values.
    [ "$_launch_port" != 1067 ] || set -- --dhcp-alternate-port=1067,68
    # Explicit PID and lease paths + system/wifi match the successful car test.
    # RDWR FIFO holds stdin open without a second writer or an EOF busy loop.
    (
        # Some ksh variants replace background-command fd 0 with /dev/null
        # despite a direct <> redirect. Open a separate fd before duplicating.
        exec 9<> "$DHCPT/stdin" || exit 1
        exec "$R/system/bin/dnsmasq" --keep-in-foreground --no-resolv --no-poll --dhcp-authoritative \
            --port=0 --user=system --group=wifi --pid-file="$DHCPT/native.pid" --dhcp-leasefile="$DHCPT/leases" \
            --interface=wlan0 --bind-interfaces \
            --dhcp-range=192.168.43.10,192.168.43.50,255.255.255.0,1h \
            --dhcp-option=3 --dhcp-option=6 "$@" <&9 9>&-
    ) > "$BK/dhcp.raw" 2>&1 &
    _newdhcp=$!
    echo "$_newdhcp $(boot_id)" > "$BK/bridge-dhcp.pid"
    sleep 1
    if [ "$(owned_dhcp_pid)" != "$_newdhcp" ]; then
        event "bridge_dhcp_start_failed port=$_launch_port stage=$(dhcp_stage) reason=$(dhcp_error)"
        record_dhcp_failure "$_launch_port"
        return 1
    fi
    return 0
}
start_bridge_dhcp() {
    [ -z "$(kp_dhcp_pid)" ] || return 0
    _newdhcp=$(owned_dhcp_pid)
    if [ -n "$_newdhcp" ]; then
        if proc_arg "$_newdhcp" --dhcp-alternate-port=1067,68; then
            dhcp_nat_on || { stop_owned_dhcp; return 1; }
        fi
        mkdir -p "$KPW" && echo "$_newdhcp $(boot_id)" > "$KPW/dnsmasq.pid" || return 1
        event bridge_dhcp_readopted
        return 0
    fi
    prepare_dhcp || { event dhcp_runtime_prepare_failed; return 1; }
    [ -x "$R/system/bin/dnsmasq" ] || { event dhcp_binary_missing; return 1; }
    dhcp_nat_off
    if ! launch_bridge_dhcp 67; then
        # Only the exact DHCP bind error permits this path. DNS, netlink,
        # permissions and unidentified failures never trigger port translation.
        [ "$(dhcp_error):$(dhcp_stage)" = address_in_use:dhcp_bind ] || return 1
        dhcp_nat_on || return 1
        if ! launch_bridge_dhcp 1067; then dhcp_nat_off; return 1; fi
    fi
    _existing=$(kp_dhcp_pid)
    if [ -n "$_existing" ] && [ "$_existing" != "$_newdhcp" ]; then
        stop_owned_dhcp
        event bridge_dhcp_yielded
        return 0
    fi
    # KP 1.7.4 adopts a live dnsmasq by PID + boot ID. It retains ownership of
    # AP stop/restart; this avoids two DHCP managers continually replacing it.
    mkdir -p "$KPW" || { stop_owned_dhcp; return 1; }
    echo "$_newdhcp $(boot_id)" > "$KPW/dnsmasq.pid.bridge-$$" &&
        mv "$KPW/dnsmasq.pid.bridge-$$" "$KPW/dnsmasq.pid" || { stop_owned_dhcp; return 1; }
    event "bridge_dhcp_started port=$_launch_port"
}
maintain_kp_ap() {
    # Do not create an AP or DHCP before KP's own checked setup/hostapd starts,
    # during maintenance, or while a stock/other hotspot is running.
    if ! our_wlan || [ -f "$BK/maintenance" ] ||
        [ ! -f "$R/data/hmgapi/mods/wireless-carplay-aa/mod.json" ] ||
        [ -f "$R/data/hmgapi/mods/wireless-carplay-aa/.disabled" ] ||
        [ "$(getprop persist.sys.iap2.wifi 2>/dev/null)" != t ] ||
        [ -z "$(kp_host_pids)" ] || other_host_on; then
        DHCP_MISSING_AT=
        stop_owned_dhcp
        return 0
    fi
    if ! ap_has_ip; then
        if bb ifconfig wlan0 192.168.43.1 netmask 255.255.255.0 up >/dev/null 2>&1 && ap_has_ip; then
            event ap_address_restored
        else
            return 0
        fi
    fi
    _active_dhcp=$(kp_dhcp_pid)
    if [ -n "$_active_dhcp" ]; then
        # A replacement normal-port KP server must receive port 67 directly.
        if [ "$_active_dhcp" != "$(owned_dhcp_pid)" ]; then stop_owned_dhcp
        elif proc_arg "$_active_dhcp" --dhcp-alternate-port=1067,68; then
            dhcp_nat_on || stop_owned_dhcp
        else dhcp_nat_off; fi
        DHCP_MISSING_AT=
        return 0
    fi
    if [ -n "$(owned_dhcp_pid)" ]; then
        start_bridge_dhcp
        DHCP_MISSING_AT=
        return 0
    fi
    _now=$(up_seconds) || return 0
    [ -n "$DHCP_MISSING_AT" ] || DHCP_MISSING_AT=$_now
    [ $((_now - DHCP_MISSING_AT)) -ge 10 ] || return 0
    [ -z "$DHCP_TRIED_AT" ] || [ $((_now - DHCP_TRIED_AT)) -ge 30 ] || return 0
    DHCP_TRIED_AT=$_now
    start_bridge_dhcp
}
ap_diagnostics() {
    echo "kp_hostapd=$([ -n "$(kp_host_pids)" ] && echo yes || echo no)"
    echo "ap_ipv4=$(our_wlan && ap_has_ip && echo yes || echo no)"
    _diagpid=$(kp_dhcp_pid)
    echo "dhcp_running=$([ -n "$_diagpid" ] && echo yes || echo no)"
    if [ -z "$_diagpid" ]; then echo dhcp_source=none
    elif [ "$(owned_dhcp_pid)" = "$_diagpid" ]; then echo dhcp_source=bridge
    else echo dhcp_source=korea_projection; fi
    _leases=0
    if [ -r "$DHCPT/leases" ]; then
        while IFS= read -r _lease; do [ -z "$_lease" ] || _leases=$((_leases+1)); done < "$DHCPT/leases"
    fi
    echo "bridge_dhcp_lease_count=$_leases"
    if [ -n "$_diagpid" ] && [ "$(owned_dhcp_pid)" = "$_diagpid" ]; then echo bridge_dhcp_lease_count_applicable=yes
    else echo bridge_dhcp_lease_count_applicable=no; fi
    echo "bridge_dhcp_error=$(dhcp_error)"
    echo "bridge_dhcp_error_stage=$(dhcp_stage)"
    _port=none
    if [ -n "$_diagpid" ]; then
        _port=67
        proc_arg "$_diagpid" --dhcp-alternate-port=1067,68 && _port=1067
    fi
    echo "dhcp_server_port=$_port"
    dhcp_nat_diagnostics
    _u53=0; _u67=0; _u1067=0
    for _udp in "$PROC/net/udp" "$PROC/net/udp6"; do
        [ -r "$_udp" ] || continue
        while read -r _slot _local _rest; do
            case "$_local" in *:0035) _u53=$((_u53+1)) ;; *:0043) _u67=$((_u67+1)) ;; *:042B) _u1067=$((_u1067+1)) ;; esac
        done < "$_udp"
    done
    echo "udp53_sockets=$_u53"
    echo "udp67_sockets=$_u67"
    echo "udp1067_sockets=$_u1067"
}
