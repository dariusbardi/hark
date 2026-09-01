**Wenn du Hark auf macOS 15 oder neuer installierst: die Anleitung in 1.2 war
falsch.** Der Rechtsklick auf „Öffnen" funktioniert dort nicht mehr, Apple hat
ihn in Sequoia entfernt. Unten steht der richtige Weg.

### Was repariert wurde

**Zwei Stimmen gleichzeitig.** Seit 1.2 sucht Hark eine Stimme, die zur Sprache
des Textes passt. Lief dabei gerade eine Piper-Stimme, wurde die nicht gestoppt
— beide redeten übereinander. Jetzt nicht mehr.

**Eine Spaßstimme als Vorleser.** Bei der automatischen Wahl konnte Hark auf
Zarvox oder Bubbles landen: macOS führt die Jux-Stimmen in derselben Liste, und
auf einem Mac ohne heruntergeladene Stimmen sind alle gleich bewertet. Die sind
jetzt aussortiert.

**Der Absender verfälschte die Spracherkennung.** Bei „Bazo schreibt: …" wurde
der deutsche Vorspann mitgeprüft. Bei einer kurzen englischen Nachricht reichte
das, um die Sprache falsch zu raten. Geprüft wird jetzt nur die Nachricht.

**Der Mac blieb laut.** Wer Hark mitten im Vorlesen beendete, behielt die
hochgedrehte Lautstärke. Jetzt wird sie beim Beenden zurückgesetzt.

**„Vorlesen abbrechen" verschluckte Nachrichten.** Wartende Postfach-Nachrichten
waren danach spurlos weg — ihre Dateien sind ja schon gelöscht. Sie landen jetzt
im Verlauf, als „übersprungen".

**Die Update-Anfrage trug doch etwas bei sich.** In der Datenschutzerklärung
stand, sie sende nichts. macOS hängte von sich aus App-Name, exakte Version und
Betriebssystem-Bau an. Steht jetzt nur noch „Hark" drin, und damit stimmt die
Erklärung wieder.

---

**Installation:** `Hark-1.3.dmg` laden, Hark nach *Programme* ziehen — wirklich
ziehen, nicht aus dem Fenster der Datei heraus starten, sonst merkt sich macOS
die Erlaubnisse hinterher nicht.

**Beim ersten Start blockiert macOS.** Einmal doppelklicken und die Ablehnung
wegklicken, dann **Systemeinstellungen → Datenschutz & Sicherheit** öffnen, ganz
nach unten scrollen, dort steht Hark mit einem Knopf **„Trotzdem öffnen"**.
Draufklicken, bestätigen. Nur beim allerersten Mal.

*(Bis macOS 14 ging auch Rechtsklick → Öffnen. Ab macOS 15 nicht mehr.)*

Oder selbst bauen, dann kommt gar keine Warnung:

```
git clone https://github.com/dariusbardi/hark
cd hark
./build.sh
```

Braucht macOS 14 oder neuer.
