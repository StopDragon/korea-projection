# SPDX-License-Identifier: AGPL-3.0-only
# Input: logcat -v time. Output: timestamps + fixed categories only.
# Never export a message, address, name, coordinate or exception payload.
function put(code, time) {
    time=$2
    if (time !~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9]+$/) time="unavailable"
    ring[n%40]="projection_event_time=" time " code=" code; n++
}
{
    l=tolower($0)
    if (l ~ /[vdiwef]\/(wifihw|wifistatemachine|wificontroller|wifinative[^ (]*|wifiservice|softapcontroller)[ (]/) {
        if (l ~ /unload.*driver|driver.*unload/) put("wifi_driver_unload")
        else if (l ~ /load.*driver|driver.*load/) put("wifi_driver_load")
        else if (l ~ /setwifiapenabled|softap.*start|softap.*stop/) put("wifi_ap_transition")
        else if (l ~ /supplicant.*stop|supplicant.*terminat/) put("wifi_supplicant_stop")
        else if (l ~ /error|fail/) put("wifi_framework_error")
        next
    }
    if (l ~ /[vdiwef]\/(surfaceflinger|bufferqueue|omx[^ (]*|vpu[^ (]*|mediacodec|tccvideo[^ (]*)[ (]/ && l ~ /error|fail|timeout|timed out|stuck|deadlock/) {
        put("video_stack_error"); next
    }
    focus=(l ~ /carplay|tcccarplay|hkmc[_ .-]*gpm|hkmc\.gpm|iap2|dipo|phoneprojection|[vdiwef]\/gpm[ (]/)
    if (!focus) next
    if (l ~ /fatal signal|sigsegv|sigabrt|abort message|fatal exception/) put("fatal")
    else if (l ~ /androidruntime/ && l ~ /process:|exception|caused by:/) put("java_failure")
    else if (l ~ /activitymanager/ && l ~ /has died|force finishing|anr in|crash/) put("process_exit_or_anr")
    else if (l ~ /network is unreachable|no route to host|enetunreach|ehostunreach/) put("route_error")
    else if (l ~ /decoder|mediacodec|vpu|h264|video/ && l ~ /error|fail|unsupported|invalid/) put("video_error")
    else if (l ~ /rtsp|socket|transport/ && l ~ /error|fail|closed|reset|broken pipe/) put("transport_error")
    else if (l ~ /timeout|timed out|time out/) put("timeout")
}
END {
    print "projection_filtered_event_count=" n+0
    start=(n>40?n-40:0)
    for(i=start;i<n;i++) print ring[i%40]
}
