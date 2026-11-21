#!/bin/bash
# Build the dongle package with its HMG-API mod inside:
# javac (Java 8) -> d8 (min API 19) -> hooks.jar -> sign -> ../pkg/mod/package.zip -> ../USB/packages/usbwifi.hotspot.zip -> descriptor check.
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"          # hmgapi_mod
PK="$B/../pkg"
# settings (environment): ANDROID_SDK, AAKEEP_KEY (your own EC P-256 PEM key), OUT_ZIP, NEMESIS_SRC + DESC_CHECKER (optional check)
SDK="${ANDROID_SDK:-$HOME/Library/Android/sdk}"
AJ="$SDK/platforms/android-35/android.jar"
D8="$SDK/build-tools/36.0.0/d8"
P="${NEMESIS_SRC:-}"          # NEMESIS source: Sources/native
CHK="${DESC_CHECKER:-}"       # folder with check.c
KEY="${AAKEEP_KEY:-$B/keys/aakeep-author.key}"
rm -rf "$B/build"; mkdir -p "$B/build/stubs" "$B/build/cls" "$B/build/dex"
javac --release 8 -nowarn -d "$B/build/stubs" -cp "$AJ" $(find "$B/stubs" -name '*.java')
javac --release 8 -Xlint:-options -d "$B/build/cls" -cp "$AJ:$B/build/stubs" $(find "$B/src" -name '*.java')
"$D8" --min-api 19 --release --lib "$AJ" --classpath "$B/build/stubs" --output "$B/build/dex" $(find "$B/build/cls" -name '*.class')
rm -f "$B/mod/pk/hooks.jar"; (cd "$B/build/dex" && zip -X -q "$B/mod/pk/hooks.jar" classes.dex)
rm -rf "$B/mod/pk/META-HMGAPI"
python3 -I "$B/tools/sign.py" "$B/mod/pk" "$KEY"
mkdir -p "$PK/mod"
rm -f "$PK/mod/package.zip"; (cd "$B/mod/pk" && zip -X -D -q "$PK/mod/package.zip" META-HMGAPI/manifest.json META-HMGAPI/signature hooks.jar mod.json settings.json)
echo ev6-kr-aa-keep > "$PK/mod/id"
chmod 755 "$PK/scripts/"*.sh "$PK/svc/dongle.sh" "$PK/bin/"*.sh
if [ -d "$B/../USB/packages" ]; then Z="${OUT_ZIP:-$B/../USB/packages/usbwifi.hotspot.zip}"; else mkdir -p "$B/../build"; Z="${OUT_ZIP:-$B/../build/usbwifi.hotspot.zip}"; fi
rm -f "$Z"
(cd "$PK" && find . -type f ! -name .DS_Store | sed 's#^\./##' | sort | zip -X -D -q "$Z" -@)
if [ -n "$P" ] && [ -n "$CHK" ]; then
    cc -I"$P" -o "$B/build/check" "$CHK/check.c" "$P/ini.c" "$P/meta.c" 2>/dev/null
    "$B/build/check" "$PK/NEMESIS.data"
else echo "descriptor check skipped (set NEMESIS_SRC and DESC_CHECKER)"; fi
unzip -l "$Z" | grep -v source/driver
shasum -a 256 "$Z"
