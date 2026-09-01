#!/bin/zsh
cd "$(dirname "$0")"
set -e
OUT="bericht_bauen.txt"
exec > >(tee "$OUT") 2>&1

NAME="Hark"
BUNDLE="studio.bazo.hark"
VERSION="1.3"
APP="build/$NAME.app"

echo "=== $NAME $VERSION bauen  $(date) ==="
echo ""

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "-- 1. Übersetzen --"
swiftc -O \
  -o "$APP/Contents/MacOS/$NAME" \
  Sources/*.swift \
  -framework AppKit -framework AVFoundation -framework Speech -framework ServiceManagement \
  -framework NaturalLanguage
echo "   fertig: $(du -h "$APP/Contents/MacOS/$NAME" | cut -f1)"

echo ""
echo "-- 1b. Symbol bauen --"
if [[ -f Hark-Symbol.zip && ! -d Hark.iconset ]]; then
  unzip -qo Hark-Symbol.zip && echo "   Symbol-Dateien ausgepackt"
fi
if [[ -d Hark.iconset ]]; then
  iconutil -c icns Hark.iconset -o "$APP/Contents/Resources/Hark.icns" 2>&1 | tail -2
  [[ -f "$APP/Contents/Resources/Hark.icns" ]] && echo "   Hark.icns erzeugt ($(du -h "$APP/Contents/Resources/Hark.icns" | cut -f1))"
else
  echo "   (kein Symbol gefunden, baue ohne)"
fi

echo ""
echo "-- 2. Info.plist schreiben --"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>Hark</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>BAZO</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Hark hört auf dein Weckwort und schreibt auf, was du danach sagst. Alles bleibt auf diesem Mac.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Hark wandelt deine Sprache in Text um — auf diesem Gerät, ohne Internet.</string>
</dict>
</plist>
PLIST
echo "   fertig"

echo ""
echo "-- 3. Signieren --"
ID=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"[^"]*"' | head -1 | tr -d '"')
if [[ -n "$ID" ]]; then
  echo "   mit: $ID"
  codesign --force --sign "$ID" --timestamp=none "$APP"
else
  echo "   kein Zertifikat gefunden — signiere behelfsmäßig"
  codesign --force --sign - "$APP"
fi
codesign --verify --verbose=1 "$APP" && echo "   Signatur in Ordnung"

echo ""
echo "-- 4. Installieren --"
# Am liebsten nach /Applications — dort findet macOS (und Claude) die App.
# Wenn das nicht beschreibbar ist, nach ~/Applications ausweichen.
if [[ -w /Applications ]]; then
  ZIEL="/Applications"
else
  ZIEL="$HOME/Applications"
fi
mkdir -p "$ZIEL"
# eine alte Kopie am jeweils anderen Ort wegraeumen
[[ "$ZIEL" == "/Applications" ]] && rm -rf "$HOME/Applications/$NAME.app" 2>/dev/null || true
# Erst hoeflich bitten: nur so raeumt Hark noch auf (Musik wieder anschalten).
osascript -e "tell application \"$NAME\" to quit" 2>/dev/null || true
sleep 1
killall "$NAME" 2>/dev/null || true
sleep 1
rm -rf "$ZIEL/$NAME.app"
cp -R "$APP" "$ZIEL/$NAME.app"
echo "   liegt jetzt in: $ZIEL/$NAME.app"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
{ [[ -x "$LSREG" ]] && "$LSREG" -f "$ZIEL/$NAME.app" && echo "   bei macOS angemeldet"; } || true
# Bauordner wegraeumen, sonst zeigt Spotlight die App doppelt
{ [[ -x "$LSREG" ]] && "$LSREG" -u "$PWD/$APP" 2>/dev/null; } || true
rm -rf build
echo "   Bauordner aufgeraeumt (keine doppelte Hark mehr)"

echo ""
echo "-- 5. Starten --"
open "$ZIEL/$NAME.app"
sleep 3
if pgrep -x "$NAME" >/dev/null; then
  echo "   LÄUFT — schau oben rechts in die Menüleiste, ein Ohr-Symbol."
else
  echo "   Gestartet, aber ich sehe keinen Prozess. Bitte Claude den Bericht zeigen."
fi

echo ""
echo "-- 6. Installationspaket bauen --"
DMG="Hark-$VERSION.dmg"
rm -f "$DMG"
STAGING=$(mktemp -d)
cp -R "$ZIEL/$NAME.app" "$STAGING/"
ln -s /Applications "$STAGING/Programme"
hdiutil create -quiet -volname "Hark $VERSION" -srcfolder "$STAGING" \
  -ov -format UDZO "$DMG" && echo "   fertig: $DMG ($(du -h "$DMG" | cut -f1))"
rm -rf "$STAGING"
echo "   Zum Verschicken: diese eine Datei genuegt."

# Eine Zeile pro Bau, die bleibt stehen. Der Bericht oben wird jedes Mal
# ueberschrieben — so kann Claude nachsehen, was du wirklich gebaut hast,
# statt es dir glauben zu muessen.
echo "$(date '+%Y-%m-%d %H:%M')  $VERSION  gebaut" >> bau-verlauf.txt

echo ""
echo "=== Ende ==="
echo ""
echo "  Sag Claude: hark gebaut"
echo ""

# Fenster zumachen. Das hier laeuft nur, wenn alles geklappt hat: bei einem
# Fehler bricht das Skript vorher ab (set -e), und dann bleibt das Fenster
# offen, damit du die Meldung noch lesen kannst.
echo "  (Fenster schliesst sich gleich von allein)"
( sleep 3
  osascript -e 'tell application "Terminal" to close (every window whose name contains "HARK BAUEN")' \
    >/dev/null 2>&1 ) &
