#!/system/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Install only the original signed EV6 helper after its original stock-file gate.
export PATH=${KP_PERSONAL_TEST_PATH:-/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin}
R=${G70_DIAG_TEST_ROOT:-${KP_PERSONAL_TEST_ROOT:-}}
P=${KP_PERSONAL_APP:-$R/data/nemesis/apps/korea.projection}
[ -d "$P" ] || P=$R/data/nemesis/packages/korea.projection
. "$P/usb/profiles.sh"
[ "$1" != install ] || [ "$KP_PROFILE" = ev6 ] || exit 1
H=$R/system/bin/hmgapid
[ -x "$H" ] || exit 1
B=$R/data/nemesis/backup/korea.projection/usb-ev6
mkdir -p "$B" || exit 1
ID=ev6-kr-aa-keep
Z=$KP_APP/usb/ev6/mod/package.zip
BB=$KP_APP/bin/busybox
plan_safe() {
    "$H" engine plan > "$B/helper-plan.txt" 2>&1 || return 1
    _bad=0
    while IFS= read -r _l; do
        case "$_l" in
            'problem  '*|'rebase   '*) _bad=1 ;;
            'change   '*|'update   '*|'setting  '*|'bind     '*|'unbind   '*|'restore  '*)
                case "$_l" in *"[$ID]"*) ;; *) _bad=1 ;; esac ;;
        esac
    done < "$B/helper-plan.txt"
    [ "$_bad" = 0 ]
}
case "$1" in
    install)
        cd "$KP_APP/usb/ev6" || exit 1
        ROOT=$R
        . ./kr/modgate.sh
        mod_gate || exit 1
        set -- $("$BB" md5sum "$Z" 2>/dev/null)
        [ "$1" = 623a24318f900202ad2158cea0054d89 ] || exit 1
        _new=0; [ -d "$R/data/hmgapi/mods/$ID" ] || _new=1
        "$H" engine install "$Z" --from-nemesis || exit 1
        mkdir -p "$KP_APP/mod" && echo "$ID" > "$KP_APP/mod/id"
        [ "$_new" != 1 ] || : > "$B/helper-owned"
        ;;
    remove)
        [ -f "$B/helper-owned" ] || exit 0
        for part in mod.json hooks.jar; do
            expected=$("$BB" unzip -p "$Z" "$part" | "$BB" md5sum); expected=${expected%% *}
            actual=$("$BB" md5sum "$R/data/hmgapi/mods/$ID/$part" 2>/dev/null); actual=${actual%% *}
            [ -n "$actual" ] && [ "$actual" = "$expected" ] || { echo 'EV6 helper was replaced; preserving it.'; exit 1; }
        done
        "$H" engine remove "$ID" --from-nemesis || exit 1
        ;;
    *) exit 1 ;;
esac
if plan_safe; then
    "$H" engine apply || exit 1
else
    echo 'EV6 helper: other pending HMG-API changes; use HMG-API Apply after reviewing them.'
    exit 1
fi
exit 0
