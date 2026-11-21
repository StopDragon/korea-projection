# SPDX-License-Identifier: AGPL-3.0-only
kp_projection_count() {
    _kc=$(value "$KPW/cpn")
    case "$_kc" in ''|*[!0-9]*) echo unavailable ;; *) echo "$_kc" ;; esac
}
carplay_ipv6_count() {
    if [ ! -r "$PROC/net/if_inet6" ] || [ ! -r "$PROC/net/tcp6" ]; then echo 0; return 0; fi
    # if_inet6 uses network byte order; tcp6 prints each 32-bit word in host
    # byte order on this ARM little-endian unit. IPv4-mapped sessions remain
    # in the existing IPv4 counter and are not counted here a second time.
    _v6result=$(bb awk '
      function proc_hex(h, i,j,out) {
        out=""; h=toupper(h)
        for(i=1;i<=32;i+=8) for(j=6;j>=0;j-=2) out=out substr(h,i+j,2)
        return out
      }
      FILENAME ~ /if_inet6$/ {if($6=="wlan0") addresses[proc_hex($1)]=1; next}
      $4=="01" {split($2,a,":"); if(a[2]=="1B58" && (toupper(a[1]) in addresses)) n++}
      END {print n+0}' "$PROC/net/if_inet6" "$PROC/net/tcp6" 2>/dev/null)
    case "$_v6result" in ''|*[!0-9]*) echo 0 ;; *) echo "$_v6result" ;; esac
}
usb_projection_diagnostics() {
    echo "wlan0_ifindex=$(value "$NET/wlan0/ifindex")"
    _found=no; USB_DIAG_PORT=
    for _ud in "$R"/sys/bus/usb/devices/*; do
        _usb_id=$(value "$_ud/idVendor"):$(value "$_ud/idProduct")
        kp_cap_ac_id "$_usb_id" || kp_cap_ax_id "$_usb_id" || continue
        USB_DIAG_PORT=${_ud##*/}
        _found=yes
        for _attr in busnum devnum authorized speed; do
            _uv=$(value "$_ud/$_attr")
            case "$_uv" in ''|*[!0-9]*) _uv=unavailable ;; esac
            echo "dongle_${_attr}=$_uv"
        done
        _uv=$(value "$_ud/power/control")
        case "$_uv" in on|auto) ;; *) _uv=unavailable ;; esac
        echo "dongle_power_control=$_uv"
        _uv=$(value "$_ud/power/runtime_status")
        case "$_uv" in active|suspended|suspending|resuming|unsupported) ;; *) _uv=unavailable ;; esac
        echo "dongle_runtime_status=$_uv"
        break
    done
    echo "dongle_usb_present=$_found"
    [ -n "$USB_DIAG_PORT" ] || USB_DIAG_PORT=$(value "$BK/selected-usb-port")
    case "$USB_DIAG_PORT" in ''|*[!0-9.-]*) USB_DIAG_PORT=unavailable ;; esac
}
projection_extra_diagnostics() {
    bb awk 'NR==1 && $1 ~ /^[0-9.]+$/ { print "host_load_1m=" $1 }' "$PROC/loadavg" 2>/dev/null
    bb awk '$1=="MemAvailable:" && $2 ~ /^[0-9]+$/ {print "host_memavailable_kb=" $2} $1=="MemFree:" && $2 ~ /^[0-9]+$/ {print "host_memfree_kb=" $2}' "$PROC/meminfo" 2>/dev/null
    bb awk '/^[ \t]*wlan0:/ {sub(/^[ \t]*wlan0:[ \t]*/, ""); n=split($0,a,/[ \t]+/); if(n>=12) {print "wifi_rx_bytes=" a[1]; print "wifi_tx_bytes=" a[9]; print "wifi_rx_errors=" a[3]; print "wifi_rx_dropped=" a[4]; print "wifi_tx_errors=" a[11]; print "wifi_tx_dropped=" a[12]}}' "$PROC/net/dev" 2>/dev/null
    bb awk '$1=="Tcp:" && $2 !~ /^[0-9-]+$/ {for(i=2;i<=NF;i++) h[i]=$i; next}
      $1=="Tcp:" {for(i=2;i<=NF;i++) if(h[i] ~ /^(InCsumErrors|InErrs|RetransSegs)$/ && $i ~ /^[0-9]+$/) print "tcp_" h[i] "=" $i}' "$PROC/net/snmp" 2>/dev/null
    bb awk '$1=="wlan0:" {for(i=3;i<=4;i++) if($i ~ /^-?[0-9]+[.]?$/) {v=$i;sub(/[.]$/,"",v);print (i==3?"wifi_quality_raw=":"wifi_signal_raw=") v}}' "$PROC/net/wireless" 2>/dev/null
    echo "kp_sampled_carplay_connections=$(kp_projection_count)"
    projection_route_diagnostics
    usb_projection_diagnostics
    logcat -d -v time 2>/dev/null | bb awk -f "$APP/bin/filter-projection.awk"
    dmesg 2>/dev/null | bb awk -v usb_port="$USB_DIAG_PORT" -f "$APP/bin/filter-usb.awk"
}
record_projection_snapshot() {
    case "$1" in connection-up|connection-down|interface-loss|interface-replaced) ;; *) return 1 ;; esac
    evidence_init || return 0
    for _sn in 1 2; do
        _spth="$BK/auto-current/$1-$_sn.txt"
        [ ! -f "$_spth" ] || continue
        evidence_snapshot > "$_spth.tmp" && mv "$_spth.tmp" "$_spth"
        break
    done
    return 0
}
monitor_projection() {
    _mo_age=$(up_seconds) || return 0
    [ "$_mo_age" -ge 150 ] && our_wlan && ap_has_ip && [ -n "$(kp_host_pids)" ] || return 0
    _observed=$(($(carplay_ipv4_count) + $(carplay_ipv6_count)))
    if [ -z "$PROJECTION_LAST" ]; then
        PROJECTION_LAST=$_observed
        [ "$_observed" -eq 0 ] || record_projection_snapshot connection-up
    elif [ "$_observed" != "$PROJECTION_LAST" ]; then
        PROJECTION_LAST=$_observed
        if [ "$_observed" -gt 0 ]; then record_projection_snapshot connection-up
        else record_projection_snapshot connection-down; fi
    fi
    return 0
}
