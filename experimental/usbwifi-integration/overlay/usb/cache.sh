#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Persistent evidence, never executable shell input or a driver-load authority.
export PATH=${KP_PERSONAL_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
R=${G70_DIAG_TEST_ROOT:-${KP_PERSONAL_TEST_ROOT:-}}
P=${KP_PERSONAL_APP:-$R/data/nemesis/apps/korea.projection}
[ -d "$P" ] || P=$R/data/nemesis/packages/korea.projection
. "$P/usb/profiles.sh"
BB=$KP_APP/bin/busybox
CACHE_DIR=$R/data/nemesis/backup/korea.projection/compatibility-memory
umask 077
cache_value() { [ ! -r "$2" ] || "$BB" awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/, ""); print; exit}' "$2"; }
cache_hash() { set -- $("$BB" md5sum "$1" 2>/dev/null); echo "${1:-unavailable}"; }
cache_tree_hash() {
    [ -d "$1" ] || { echo unavailable; return; }
    "$BB" find "$1" -type f -exec "$BB" md5sum '{}' + 2>/dev/null | "$BB" sort | "$BB" md5sum | { read -r _h _rest; case "$_h" in ''|d41d8cd98f00b204e9800998ecf8427e) echo unavailable ;; *) echo "$_h" ;; esac; }
}
cache_script_hash() {
    "$BB" find "$1" -type f '(' -name '*.sh' -o -name '*.awk' ')' -exec "$BB" md5sum '{}' + 2>/dev/null | "$BB" sort | "$BB" md5sum | { read -r _h _rest; echo "${_h:-unavailable}"; }
}
cache_public() {
    echo record_scope=last_saved_observation
    echo live_eligibility_from_cache=no
    for k in selected_profile current_evidence highest_observed cache_reused failure_state failure_boots user_reported_display user_reported_stable_minutes user_reported_failure; do
        v=$(cache_value "$k" "$CACHE_DIR/last.ini")
        case "$v" in ''|*[!A-Za-z0-9_.:-]*) v=unknown ;; esac
        echo "$k=$v"
    done
    echo 'automatic_screen_verification=no'
}
case "$1" in
    --print) cache_public; exit 0 ;;
    --template)
        echo "fingerprint=$(cache_value fingerprint "$CACHE_DIR/last.ini")"
        echo display_confirmed=no
        echo stable_minutes=0
        echo problem=none
        exit 0 ;;
    --import)
        f=$2
        token=$(cache_value fingerprint "$f")
        [ -n "$token" ] && [ "$token" = "$(cache_value fingerprint "$CACHE_DIR/last.ini")" ] || exit 1
        display=$(cache_value display_confirmed "$f")
        problem=$(cache_value problem "$f")
        case "$display:$problem" in yes:|yes:none|no:screen_freeze) ;; *) exit 1 ;; esac
        minutes=$(cache_value stable_minutes "$f")
        case "$minutes" in ''|*[!0-9]*) exit 1 ;; esac
        [ "${#minutes}" -le 4 ] && [ "$minutes" -le 1440 ] || exit 1
        mkdir -p "$CACHE_DIR" || exit 1
        { echo "fingerprint=$token"; echo "user_reported_display=$display"; echo "user_reported_stable_minutes=$minutes"; echo "user_reported_failure=${problem:-none}"; } > "$CACHE_DIR/user-report.tmp.$$" &&
            mv "$CACHE_DIR/user-report.tmp.$$" "$CACHE_DIR/user-report.pending"
        # Applied only after the same hardware/software fingerprint is checked again.
        exit $? ;;
    --reset) rm -f "$CACHE_DIR/last.ini" "$CACHE_DIR/user-report.pending"; exit 0 ;;
    --observe) ;;
    *) exit 1 ;;
esac
case "$KP_PROFILE" in g70|generic-usb|nx4|ev6|native) ;; *) exit 0 ;; esac
# A missing/changed USB radio cannot reuse a cached eligibility decision.
C_USB_ID=native; C_USB_CLASS=native; C_FAMILY=native
if [ "$KP_PROFILE" != native ]; then
    kp_cap_usb_scan || exit 0
    [ "$KPC_USB_COUNT" = 1 ] || exit 0
    C_USB_ID=$KPC_USB_ID; C_FAMILY=$KPC_FAMILY
    C_DEVICE=
    for d in "$R"/sys/bus/usb/devices/*; do
        [ "$(cat "$d/idVendor" 2>/dev/null):$(cat "$d/idProduct" 2>/dev/null)" != "$C_USB_ID" ] || C_DEVICE=$d
    done
    C_USB_CLASS=unknown
    for d in "$C_DEVICE":*; do
        c=$(cat "$d/bInterfaceClass" 2>/dev/null):$(cat "$d/bInterfaceSubClass" 2>/dev/null):$(cat "$d/bInterfaceProtocol" 2>/dev/null)
        [ "$c" != ff:ff:ff ] || C_USB_CLASS=$c
    done
    [ "$C_USB_CLASS" = ff:ff:ff ] || exit 0
fi
mkdir -p "$CACHE_DIR" || exit 1
C_FACTS=$CACHE_DIR/facts.tmp.$$
trap 'rm -f "$C_FACTS" "$CACHE_DIR/last.tmp.$$"' EXIT
C_DRIVER=$R/system/wifi/bcmdhd.ko
if [ "$KP_PROFILE" != native ]; then
    C_DRIVER=$KP_APP/usb/g70/modules/$C_FAMILY.ko
    if [ "$C_FAMILY" = 88x2bu ] && [ "$(cat "$KP_USB_STATE/driver-profile" 2>/dev/null)" = baseline ]; then C_DRIVER=$KP_APP/usb/g70/modules/88x2bu-baseline.ko; fi
fi
C_CONFIG=$(cache_hash "$R/proc/config.gz")
C_STOCK=$(cache_hash "$R/system/wifi/bcmdhd.ko")
C_MAPS=$(cache_tree_hash "$R/data/hmgapi/maps")
C_MODE=$(cache_tree_hash "$R/data/hmgapi/mods/wireless-carplay-aa")
C_HMG=$(cache_hash "$R/data/hmgapi/installed")
C_CODE=$(cache_tree_hash "$KP_APP/svc")
{
    echo schema=1
    echo code_version=1.7.4.2
    echo "code_bundle=$(cat "$KP_APP/CODE_FINGERPRINT" 2>/dev/null)"
    echo "code_runtime=$C_CODE"
    echo "code_usb=$(cache_script_hash "$KP_APP/usb")"
    echo "product=$KP_PRODUCT"
    echo "platform=$(getprop ro.board.platform 2>/dev/null)"
    echo "android=$(getprop ro.build.version.release 2>/dev/null)"
    echo "kernel=$(cat "$R/proc/sys/kernel/osrelease" 2>/dev/null)"
    echo "kernel_config=$C_CONFIG"
    echo "stock_module=$C_STOCK"
    echo "driver=$(cache_hash "$C_DRIVER")"
    echo "ap_query_tool=$(cache_hash "$KP_APP/usb/g70/bin/ap-capabilities")"
    echo "ap_control_tool=$(cache_hash "$KP_APP/usb/g70/bin/ctrl-status")"
    echo "usb_id=$C_USB_ID"
    echo "usb_class=$C_USB_CLASS"
    echo "mode=$C_MODE"
    echo "maps=$C_MAPS"
    echo "hmg_installed=$C_HMG"
    echo "helper_mode=$(cache_tree_hash "$R/data/hmgapi/mods/ev6-kr-aa-keep")"
} > "$C_FACTS" || exit 1
C_FP=$(cache_hash "$C_FACTS")
C_REUSED=no
C_SETUP_READY=no
if [ -s "$R/data/hmgapi/mods/wireless-carplay-aa/mod.json" ] && [ ! -f "$R/data/hmgapi/mods/wireless-carplay-aa/.disabled" ] && [ "$(getprop persist.sys.iap2.wifi 2>/dev/null)" = t ]; then C_SETUP_READY=yes; fi
C_PROGRESS_BOOT=$(cache_value boot "$R/data/local/tmp/korea-projection-progress.txt")
C_THIS_BOOT=$(cat "$R/proc/sys/kernel/random/boot_id" 2>/dev/null)
C_PROGRESS_STATE=unknown
if [ "$C_PROGRESS_BOOT" = "$C_THIS_BOOT" ] && [ -n "$C_THIS_BOOT" ]; then
    C_PROGRESS_STATE=$(cache_value state "$R/data/local/tmp/korea-projection-progress.txt")
    case "$C_PROGRESS_STATE" in run|reboot|fail) C_SETUP_READY=no ;; esac
fi
C_PREV_FP=$(cache_value fingerprint "$CACHE_DIR/last.ini")
C_FAILURE=none
[ "$C_PROGRESS_STATE" != fail ] || C_FAILURE=hmg_setup_failed
if [ "$KP_PROFILE" != native ]; then
    case "$(cat "$KP_USB_STATE/state.txt" 2>/dev/null)" in
        *blocked*|*failed*|*incompatible*|*unsupported*|*unfinished*|*requires_reboot*|*reboot_required*|*file_changed*|cannot_*) C_FAILURE=controller_protected ;;
    esac
    [ ! -f "$KP_USB_STATE/blocked" ] && [ ! -f "$KP_USB_STATE/load-pending" ] || C_FAILURE=controller_protected
fi
if [ "$C_FP" = "$C_PREV_FP" ] && [ "$(cache_value selected_profile "$CACHE_DIR/last.ini")" = "$KP_PROFILE" ] &&
    [ "$(cache_value failure_state "$CACHE_DIR/last.ini")" = none ] && [ "$C_FAILURE" = none ]; then
    case "$C_CONFIG:$C_STOCK:$C_MAPS:$C_MODE:$C_HMG" in *unavailable*) ;; *) C_REUSED=yes ;; esac
fi
# Read-only live evidence. TCP/control readiness never means responsive video.
APP=$KP_APP
HOTSPOT_LIB=1 . "$KP_APP/svc/hotspot.sh"
C_BIND=no
if [ "$KP_PROFILE" = native ]; then
    KPC_ROOT=$R; kp_cap_native_available && C_BIND=yes
else
    m=$(readlink "$R/sys/class/net/wlan0/device/driver/module" 2>/dev/null)
    b=$(cat "$R/proc/sys/kernel/random/boot_id" 2>/dev/null)
    [ "${m##*/}" = "$C_FAMILY" ] &&
        [ "$(cat "$KP_USB_STATE/loaded-boot" 2>/dev/null)" = "$b:$(cache_hash "$C_DRIVER")" ] && C_BIND=yes
    if ! (
        KP_USB_BACKEND_PROFILE=$KP_PROFILE
        . "$KP_APP/usb/g70/bin/common.sh"
        compatible && single_tested_dongle && tested_usb_net "$NET/wlan0" &&
            [ "$(md5_of "$APP/modules/$G70_KO")" = "$G70_KO_MD5" ]
    ); then C_FAILURE=compatibility_recheck_failed; fi
fi
[ "$C_BIND" = yes ] || C_REUSED=no
[ "$C_FAILURE" = none ] && [ "$C_SETUP_READY" = yes ] || C_REUSED=no
C_AP=unknown
C_CTRL=$KP_APP/usb/g70/ctrl
if [ -d "$C_CTRL" ]; then
    C_STATUS=$("$KP_APP/usb/g70/bin/ctrl-status" "$R/data/misc/wifi/hostapd/wlan0" "$C_CTRL" 2>/dev/null)
    case "$C_STATUS" in *ctrl.state=ENABLED*) C_AP=observed ;; esac
fi
C_LEASE=unknown
if [ "$KP_PROFILE" != native ]; then
    if [ -f "$KP_APP/usb/g70/dhcp-runtime/leases" ]; then
        C_LEASE=$("$BB" awk 'NF>=3 {n++} END{print n+0}' "$KP_APP/usb/g70/dhcp-runtime/leases")
    fi
fi
C_CP=$(cp_count)
case "$C_CP" in ''|*[!0-9]*) C_CP=0 ;; esac
C_LEVEL=profile_qualified; C_RANK=1
[ "$C_BIND" != yes ] || { C_LEVEL=binding_observed; C_RANK=2; }
[ "$C_BIND" != yes ] && C_AP=unknown
[ "$C_AP" != observed ] || { C_LEVEL=ap_observed; C_RANK=3; }
case "$C_LEASE" in ''|*[!0-9]*) ;; *) [ "$C_LEASE" -eq 0 ] || { C_LEVEL=lease_record_observed; C_RANK=4; } ;; esac
[ "$C_CP" -eq 0 ] || { C_LEVEL=projection_control_observed; C_RANK=5; }
C_HIGHEST=$C_LEVEL; C_HIGH_RANK=$C_RANK
C_DISPLAY=unconfirmed; C_MINUTES=0
C_USER_FAILURE=none
if [ "$C_FP" = "$C_PREV_FP" ] && [ "$(cache_value user_reported_failure "$CACHE_DIR/last.ini")" = screen_freeze ]; then C_USER_FAILURE=screen_freeze; fi
if [ "$C_REUSED" = yes ]; then
    h=$(cache_value highest_rank "$CACHE_DIR/last.ini")
    case "$h" in 1|2|3|4|5) if [ "$h" -gt "$C_RANK" ]; then C_HIGH_RANK=$h; C_HIGHEST=$(cache_value highest_observed "$CACHE_DIR/last.ini"); fi ;; esac
    C_DISPLAY=$(cache_value user_reported_display "$CACHE_DIR/last.ini")
    C_MINUTES=$(cache_value user_reported_stable_minutes "$CACHE_DIR/last.ini")
fi
if [ "$C_FAILURE" = none ] && [ "$C_BIND" = yes ] && [ "$C_SETUP_READY" = yes ] &&
    [ "$(cache_value fingerprint "$CACHE_DIR/user-report.pending")" = "$C_FP" ]; then
    C_DISPLAY=$(cache_value user_reported_display "$CACHE_DIR/user-report.pending")
    C_MINUTES=$(cache_value user_reported_stable_minutes "$CACHE_DIR/user-report.pending")
    C_USER_FAILURE=$(cache_value user_reported_failure "$CACHE_DIR/user-report.pending")
    rm -f "$CACHE_DIR/user-report.pending"
fi
if [ -f "$CACHE_DIR/user-report.pending" ] && [ "$(cache_value fingerprint "$CACHE_DIR/user-report.pending")" != "$C_FP" ]; then rm -f "$CACHE_DIR/user-report.pending"; fi
C_BOOT=$(cat "$R/proc/sys/kernel/random/boot_id" 2>/dev/null)
C_FAIL_BOOTS=0
if [ "$C_USER_FAILURE" = screen_freeze ]; then C_FAILURE=user_reported_screen_freeze; C_REUSED=no; fi
if [ "$C_FAILURE" != none ]; then
    C_DISPLAY=unconfirmed; C_MINUTES=0; C_HIGHEST=invalidated; C_HIGH_RANK=0
    n=0
    [ "$C_FP" != "$C_PREV_FP" ] || n=$(cache_value failure_boots "$CACHE_DIR/last.ini")
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    [ "${#n}" -le 3 ] || n=999
    C_FAIL_BOOTS=$n
    [ "$(cache_value failure_boot "$CACHE_DIR/last.ini")" = "$C_BOOT" ] || C_FAIL_BOOTS=$((n+1))
fi
{
    echo schema=1
    echo "fingerprint=$C_FP"
    echo "selected_profile=$KP_PROFILE"
    echo "cache_reused=$C_REUSED"
    echo "current_evidence=$C_LEVEL"
    echo "highest_observed=$C_HIGHEST"
    echo "highest_rank=$C_HIGH_RANK"
    echo "failure_state=$C_FAILURE"
    echo "failure_boots=$C_FAIL_BOOTS"
    echo "failure_boot=$C_BOOT"
    echo "user_reported_display=${C_DISPLAY:-unconfirmed}"
    echo "user_reported_stable_minutes=${C_MINUTES:-0}"
    echo "user_reported_failure=${C_USER_FAILURE:-none}"
    echo automatic_screen_verification=no
} > "$CACHE_DIR/last.tmp.$$" && mv "$CACHE_DIR/last.tmp.$$" "$CACHE_DIR/last.ini"
