# SPDX-License-Identifier: AGPL-3.0-only
# Only used after native dnsmasq reports an actual DHCP socket bind conflict.
# All rules belong to unique bridge chains and affect wlan0 DHCP traffic only.
NAT_IN=G70BR_DHCP_IN
NAT_OUT=G70BR_DHCP_OUT
NAT_FILTER=G70BR_DHCP
NAT_POLICY=port-only-dnat-v1
nat_owned() { [ "$(value "$BK/$1")" = "$(boot_id)" ]; }
dhcp_nat_off() {
    if nat_owned nat-in; then
        iptables -t nat -D PREROUTING -i wlan0 -p udp --dport 67 -j "$NAT_IN" >/dev/null 2>&1
        iptables -t nat -F "$NAT_IN" >/dev/null 2>&1
        iptables -t nat -X "$NAT_IN" >/dev/null 2>&1
    fi
    if nat_owned nat-out; then
        iptables -t nat -D POSTROUTING -o wlan0 -p udp --sport 1067 -j "$NAT_OUT" >/dev/null 2>&1
        iptables -t nat -F "$NAT_OUT" >/dev/null 2>&1
        iptables -t nat -X "$NAT_OUT" >/dev/null 2>&1
    fi
    if nat_owned nat-filter; then
        iptables -D INPUT -i wlan0 -p udp --dport 1067 -j "$NAT_FILTER" >/dev/null 2>&1
        iptables -D OUTPUT -o wlan0 -p udp --sport 1067 --dport 68 -j "$NAT_FILTER" >/dev/null 2>&1
        iptables -F "$NAT_FILTER" >/dev/null 2>&1
        iptables -X "$NAT_FILTER" >/dev/null 2>&1
    fi
    rm -f "$BK/nat-active" "$BK/nat-in" "$BK/nat-out" "$BK/nat-filter" "$BK/nat-policy"
    return 0
}
nat_build() {
    iptables -t nat -N "$NAT_IN" >/dev/null 2>&1 || return 1
    boot_id > "$BK/nat-in" || return 1
    iptables -t nat -N "$NAT_OUT" >/dev/null 2>&1 || return 1
    boot_id > "$BK/nat-out" || return 1
    iptables -N "$NAT_FILTER" >/dev/null 2>&1 || return 1
    boot_id > "$BK/nat-filter" || return 1
    # Preserve the original IP destination, especially 255.255.255.255 for
    # clients whose source is 0.0.0.0. REDIRECT changes it to the interface IP;
    # Linux 3.18 rejects that zero-source unicast before UDP/INPUT delivery.
    iptables -t nat -A "$NAT_IN" -p udp --dport 67 -j DNAT --to-destination :1067 >/dev/null 2>&1 || return 1
    iptables -t nat -A "$NAT_OUT" -p udp --sport 1067 -j SNAT --to-source 192.168.43.1:67 >/dev/null 2>&1 || return 1
    iptables -A "$NAT_FILTER" -j ACCEPT >/dev/null 2>&1 || return 1
    iptables -t nat -I PREROUTING 1 -i wlan0 -p udp --dport 67 -j "$NAT_IN" >/dev/null 2>&1 || return 1
    iptables -t nat -I POSTROUTING 1 -o wlan0 -p udp --sport 1067 -j "$NAT_OUT" >/dev/null 2>&1 || return 1
    iptables -I INPUT 1 -i wlan0 -p udp --dport 1067 -j "$NAT_FILTER" >/dev/null 2>&1 || return 1
    iptables -I OUTPUT 1 -o wlan0 -p udp --sport 1067 --dport 68 -j "$NAT_FILTER" >/dev/null 2>&1 || return 1
    echo "$NAT_POLICY" > "$BK/nat-policy" && boot_id > "$BK/nat-active"
}
dhcp_nat_on() {
    nat_owned nat-active && [ "$(value "$BK/nat-policy")" = "$NAT_POLICY" ] && return 0
    dhcp_nat_off
    if nat_build; then event dhcp_port_translation_enabled_mode_port_only_dnat; return 0; fi
    dhcp_nat_off
    event dhcp_port_translation_failed
    return 1
}
dhcp_nat_diagnostics() {
    echo "dhcp_port_translation=$(nat_owned nat-active && echo yes || echo no)"
    if nat_owned nat-active; then
        if [ "$(value "$BK/nat-policy")" = "$NAT_POLICY" ]; then echo dhcp_translation_mode=port_only_dnat
        else echo dhcp_translation_mode=legacy_or_unknown; fi
        iptables -t nat -L "$NAT_IN" -n -v -x 2>/dev/null | bb awk '$3 == "DNAT" || $3 == "REDIRECT" { print "dhcp_redirect_packets=" $1; exit }'
        iptables -t nat -L "$NAT_OUT" -n -v -x 2>/dev/null | bb awk '$3 == "SNAT" { print "dhcp_reply_packets=" $1; exit }'
        iptables -L INPUT -n -v -x 2>/dev/null | bb awk -v chain="$NAT_FILTER" '$3 == chain { print "dhcp_input_packets=" $1; exit }'
        iptables -L OUTPUT -n -v -x 2>/dev/null | bb awk -v chain="$NAT_FILTER" '$3 == chain { print "dhcp_output_packets=" $1; exit }'
    else
        echo dhcp_translation_mode=none
    fi
}
