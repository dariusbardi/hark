#!/bin/zsh
cd "$(dirname "$0")"
OUT="bericht_absturz.txt"
{
echo "=== Absturzberichte für Hark  $(date) ==="
echo ""
ORDNER="$HOME/Library/Logs/DiagnosticReports"
NEUESTE=$(ls -t "$ORDNER"/Hark* 2>/dev/null | head -3)
if [[ -z "$NEUESTE" ]]; then
  echo "Keine Berichte gefunden. Entweder ist die App nicht abgestürzt,"
  echo "sondern von macOS beendet worden, oder der Bericht kommt gleich."
  echo ""
  echo "Alle Berichte der letzten Stunde:"
  find "$ORDNER" -mmin -60 -type f 2>/dev/null | head -10
else
  for D in ${(f)NEUESTE}; do
    echo "----------------------------------------"
    echo "Datei: $(basename $D)"
    echo "----------------------------------------"
    # nur der Kopf und der abgestürzte Faden — der Rest ist Rauschen
    head -40 "$D"
    echo ""
    echo "--- Absturzstelle ---"
    grep -A 25 -m1 "Thread 0 Crashed\|\"triggered\" : true" "$D" | head -35
    echo ""
  done
fi
echo "=== Ende ==="
} > "$OUT" 2>&1
echo ""
echo "  Fertig. Sag Claude: absturz da"
echo ""
read "?  Enter zum Schliessen. "
