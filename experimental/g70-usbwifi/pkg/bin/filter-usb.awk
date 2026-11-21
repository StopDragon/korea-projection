# SPDX-License-Identifier: AGPL-3.0-only
# The only G70 data port observed in every supplied report is USB 4-1.
# Keep fixed lifecycle/error codes for this port, never raw dmesg text.
{
    l=tolower($0); code=""
    if (l !~ /usb 4-1:|usb4-port1:|usb usb4:/) next
    if (l ~ /usb disconnect/) code="disconnect"
    else if (l ~ /reset .*usb device/) code="reset"
    else if (l ~ /new .*usb device/) code="enumerated"
    else if (l ~ /over-current|overcurrent/) code="overcurrent"
    else if (l ~ /error -71|error=-71/) code="protocol_error"
    else if (l ~ /error -110|error=-110/) code="timeout"
    else if (l ~ /unable to enumerate|device descriptor read|not accepting address/) code="enumeration_error"
    if (code=="") next
    t=$0; sub(/^[^\[]*\[[ ]*/,"",t); sub(/\].*/,"",t)
    if (t !~ /^[0-9]+\.[0-9]+$/) t="unavailable"
    ring[n%24]="usb_event_uptime=" t " code=" code; n++
}
END {
    print "usb_filtered_event_count=" n+0
    start=(n>24?n-24:0)
    for(i=start;i<n;i++) print ring[i%24]
}
