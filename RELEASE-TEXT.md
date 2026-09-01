Two fixes worth shipping before more people install Hark today:

**English system prompts.** When macOS asks for microphone and speech
recognition access, Hark's explanation used to appear in German for
everyone. It now follows your system language — English everywhere,
German on German Macs. (The app's own interface already did this.)

**Only one Hark at a time.** Launching Hark now politely quits any copy
that is already running — an old build or a login-item duplicate. Two
Harks used to fight over the microphone and read aloud on top of each
other.

---

**Install:** download `Hark-1.3.1.dmg`, drag Hark into *Applications* —
actually drag it, don't launch it from inside the DMG window, or macOS
forgets the permissions afterwards.

**First launch on macOS 15+:** double-click once and dismiss the warning,
then open **System Settings → Privacy & Security**, scroll to the bottom
and click **"Open Anyway"**. Only needed once. (Up to macOS 14,
right-click → Open also works.)

Or build it yourself — then there is no warning at all:

```
git clone https://github.com/dariusbardi/hark
cd hark
./build.sh
```

Needs macOS 14 or newer.

---

*Deutsche Anleitung: siehe [Release 1.3](../../releases/tag/v1.3) — der
Installationsweg ist derselbe.*
