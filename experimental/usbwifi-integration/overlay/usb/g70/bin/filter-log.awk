# SPDX-License-Identifier: AGPL-3.0-only
# Fixed-scope KP AP log filter. Do not use for general vehicle/application logs.
{
    low = tolower($0)
    if (low ~ /ssid|passphrase|password|psk=|name|phone|imei|imsi|iccid|latitude|longitude|contacts|artist|album|title=/) next
    if ($0 ~ /장치명|기기명|폰 이름|이름/) next
    if ($0 ~ /::/) next
    gsub(/[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]/, "xx:xx:xx:xx:xx:xx")
    gsub(/[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/, "x.x.x.x")
    gsub(/"[^"]*"/, "[quoted]")
    print
}
