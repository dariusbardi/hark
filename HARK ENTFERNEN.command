#!/bin/zsh
cd "$(dirname "$0")"
BUNDLE="studio.bazo.hark"

echo ""
echo "=== Hark restlos entfernen ==="
echo ""
echo "Das wird gelöscht:"
echo "  · die App selbst"
echo "  · Piper-Motor und alle geladenen Stimmen"
echo "  · alle Einstellungen (Weckruf, Stimme, Tempo)"
echo "  · der Autostart-Eintrag"
echo "  · die erteilten Erlaubnisse (Mikrofon, Spracherkennung, Tippen)"
echo ""
echo "Deine eigenen Dateien werden NICHT angefasst."
echo ""
read "ANTWORT?Wirklich alles entfernen? (j/n) "
[[ "$ANTWORT" == "j" || "$ANTWORT" == "J" ]] || { echo "Abgebrochen."; read "?Enter"; exit 0; }

echo ""
echo "-- App beenden --"
killall Hark 2>/dev/null && echo "   beendet" || echo "   lief nicht"
sleep 1

echo ""
echo "-- Autostart abmelden --"
osascript -e 'tell application "System Events" to delete login item "Hark"' 2>/dev/null
echo "   erledigt"

echo ""
echo "-- App löschen --"
for ORT in /Applications "$HOME/Applications"; do
  if [[ -d "$ORT/Hark.app" ]]; then
    rm -rf "$ORT/Hark.app" && echo "   weg: $ORT/Hark.app"
  fi
done

echo ""
echo "-- Piper und Stimmen löschen --"
UNTER="$HOME/Library/Application Support/Hark"
if [[ -d "$UNTER" ]]; then
  echo "   $(du -sh "$UNTER" | cut -f1) werden frei"
  rm -rf "$UNTER" && echo "   weg"
else
  echo "   war nichts da"
fi

echo ""
echo "-- Vorlese-Ordner --"
VOR="$HOME/Documents/Hark"
if [[ -d "$VOR" ]]; then
  # Der liegt in deinen Dokumenten, also fasse ich ihn nicht selbst an.
  echo "   $VOR bleibt liegen — da steht nur die Vorlesedatei drin."
  echo "   Wenn du ihn nicht mehr brauchst, zieh ihn selbst in den Papierkorb."
else
  echo "   war nichts da"
fi

echo ""
echo "-- Einstellungen löschen --"
defaults delete "$BUNDLE" 2>/dev/null && echo "   weg" || echo "   war nichts da"
rm -f "$HOME/Library/Preferences/$BUNDLE.plist" 2>/dev/null
rm -rf "$HOME/Library/Caches/$BUNDLE" 2>/dev/null
rm -rf "$HOME/Library/Saved Application State/$BUNDLE.savedState" 2>/dev/null

echo ""
echo "-- Erlaubnisse zurücksetzen --"
for WAS in Microphone SpeechRecognition Accessibility ListenEvent PostEvent; do
  tccutil reset $WAS "$BUNDLE" >/dev/null 2>&1 && echo "   $WAS zurückgesetzt"
done

echo ""
echo "=== Fertig. Der Mac ist wieder wie vorher. ==="
echo ""
echo "  Beim nächsten Installieren fragt Hark alles neu ab —"
echo "  genau so, wie es dein Freund erleben würde."
echo ""
read "?  Enter zum Schliessen. "
