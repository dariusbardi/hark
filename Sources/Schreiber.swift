// Schreiber.swift — types text into whichever app is up front.

import AppKit
import ApplicationServices

@MainActor
enum Schreiber {

    /// Is Hark even allowed to send keystrokes?
    static var darfTippen: Bool { AXIsProcessTrusted() }

    /// Asks macOS for Accessibility permission (shows the dialog).
    static func erlaubnisAnfragen() {
        let schluessel = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([schluessel: true] as CFDictionary)
    }

    /// Types text character by character — without touching the clipboard.
    /// That matters: whatever the user copied stays untouched.
    static func tippe(_ text: String) {
        guard !text.isEmpty,
              let quelle = CGEventSource(stateID: .combinedSessionState) else { return }

        let einheiten = Array(text.utf16)
        var i = 0
        while i < einheiten.count {
            let bis = min(i + 16, einheiten.count)
            let stueck = Array(einheiten[i..<bis])

            for gedrueckt in [true, false] {
                guard let ereignis = CGEvent(keyboardEventSource: quelle,
                                             virtualKey: 0,
                                             keyDown: gedrueckt) else { continue }
                stueck.withUnsafeBufferPointer { puffer in
                    ereignis.keyboardSetUnicodeString(stringLength: puffer.count,
                                                     unicodeString: puffer.baseAddress)
                }
                ereignis.post(tap: .cghidEventTap)
            }
            usleep(4000)
            i = bis
        }
    }

    /// Presses the Return key.
    static func eingabe() {
        guard let quelle = CGEventSource(stateID: .combinedSessionState) else { return }
        for gedrueckt in [true, false] {
            CGEvent(keyboardEventSource: quelle, virtualKey: 36, keyDown: gedrueckt)?
                .post(tap: .cghidEventTap)
        }
    }
}
