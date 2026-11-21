# SPDX-License-Identifier: AGPL-3.0-only
# Fixed-field evidence only; raw DHCP logs and lease contents never leave car.
evidence_init() {
    _eb=$(boot_id)
    if [ "$(value "$BK/auto-current/boot.private")" != "$_eb" ]; then
        rm -rf "$BK/auto-previous"
        [ ! -d "$BK/auto-current" ] || mv "$BK/auto-current" "$BK/auto-previous" || return 1
        mkdir -p "$BK/auto-current" || return 1
        echo "$_eb" > "$BK/auto-current/boot.private" || return 1
    fi
}
socket_owners() {
    # netstat's raw address/process output stays in this pipe. Emit a port
    # and a fixed owner category only (no addresses, PIDs or process strings).
    bb netstat -lnup 2>/dev/null | bb awk '
      $1 ~ /^udp/ {
        port=$4; sub(/.*:/, "", port)
        if (port != "53" && port != "67" && port != "1067") next
        owner="other_or_unavailable"; process=$NF; sub(/.*\//, "", process)
        if (process == "dnsmasq" || process == "netd" || process == "hostapd") owner=process
        print "socket_port=" port " owner=" owner
      }'
}
evidence_snapshot() {
    echo "last_dhcp_stage=$(dhcp_stage)"
    status_text
    socket_owners
    projection_extra_diagnostics
}
record_dhcp_failure() {
    evidence_init || return 0
    for _ef in 1 2; do
        _ep="$BK/auto-current/dhcp-$1-failure-$_ef.txt"
        [ ! -f "$_ep" ] || continue
        {
            echo "attempted_dhcp_port=$1"
            evidence_snapshot
        } > "$_ep.tmp" && mv "$_ep.tmp" "$_ep"
        break
    done
    return 0
}
periodic_evidence() {
    _eu=$(up_seconds) || return 0
    evidence_init || return 0
    for _et in 180 300; do
        [ "$_eu" -ge "$_et" ] || continue
        _ep="$BK/auto-current/after-${_et}s.txt"
        [ ! -f "$_ep" ] || continue
        evidence_snapshot > "$_ep.tmp" && mv "$_ep.tmp" "$_ep"
    done
    return 0
}
