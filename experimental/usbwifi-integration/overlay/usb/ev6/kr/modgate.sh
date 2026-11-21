# usbwifi.hotspot 4.9: gate for the HMG-API mod inside this package (mod/package.zip, id ev6-kr-aa-keep), sourced by
# scripts/post.sh. The mod reads stock GPM classes by name and hooks UsbHostManager (services.odex), so both must be the
# stock files of CVEV.KOR.0000.V039.001.260902 (md5 in kr/modexpect.txt). Read-only. KitKat shell: echo and set -- only.
mg_md5() {
    mg_f=$1
    set -- $(md5 "$mg_f" 2>/dev/null)
    if [ -z "$1" ] && [ -x "${ROOT:-}/system/bin/lpatch" ]; then set -- $("${ROOT:-}/system/bin/lpatch" md5 "$mg_f" 2>/dev/null); fi
    echo "$1"
}
mod_gate() {
    mg_bad=
    mg_s=$(getprop ro.product.opt.stepofspec); [ "$mg_s" = 110 ] || mg_bad="$mg_bad stepofspec=$mg_s;"
    while read mg_want mg_path; do
        [ -n "$mg_path" ] || continue
        case $mg_want in \#*) continue ;; esac
        mg_have=$(mg_md5 "${ROOT:-}$mg_path")
        [ "$mg_have" = "$mg_want" ] || mg_bad="$mg_bad $mg_path md5=$mg_have (want $mg_want);"
    done < kr/modexpect.txt
    if [ -n "$mg_bad" ]; then
        echo "mod gate: this head unit's stock files differ from the ones the mod was made for:$mg_bad"
        return 1
    fi
    return 0
}
