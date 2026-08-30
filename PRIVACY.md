# Privacy

Hark listens continuously to your microphone. Here is exactly what that means.

## What leaves your Mac

Nothing.

Speech recognition uses Apple's on-device engine with
`requiresOnDeviceRecognition = true`. If the on-device model for your language
is missing, Hark refuses to listen rather than falling back to a network
service.

**One exception, and it is yours to make.** Settings → Accuracy has a switch
called "Better accuracy via Apple's servers". It is off. Turn it on and speech
is sent to Apple for recognition instead — noticeably more accurate, and no
longer private to your Mac. Nothing turns it on for you, and nothing hides
what it does. Text-to-speech uses Apple's local voices or, optionally, Piper —
also entirely local.

Hark has no server, no account, no analytics, no crash reporting, no update
check. It opens exactly two kinds of network connection, both only when you
press a button in Settings:

- downloading the Piper engine from the Python package index
- downloading a Piper voice from Hugging Face

## What is stored

- Your settings, in the standard macOS preferences for `studio.bazo.hark`
- Piper engine and voices, in `~/Library/Application Support/Hark/`
- Nothing else. No recordings, no transcripts, no history.

Audio is processed in memory and discarded. Hark does not write what you said
to disk, except by typing it into the app you had focused — which is the whole
point.

## Permissions and why

| Permission | Why |
|---|---|
| Microphone | to hear the wake word |
| Speech recognition | to understand what follows it, on device |
| Accessibility | to type the text into the app you are using |

"Pause listening" in the menu releases the microphone entirely. The macOS
recording indicator disappears — that is your proof, not our promise.

## Removing it

Settings → Piper → remove, then drag the app to the trash. Or run
`HARK ENTFERNEN.command` from the source folder, which also resets the granted
permissions.
