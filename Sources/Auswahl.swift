// Auswahl.swift — read the selected text aloud, from any app at all.
//
// This is the way in for everyone whose Claude has no file access — so
// anyone working in the browser. Select text, hit the keys, listen.
// No setup, no pasting, no chat that has to know anything.

import AppKit

@MainActor
enum Auswahl {

    /// Copies the selection, reads it aloud, and puts the clipboard back
    /// afterwards exactly the way it was. Anyone who had something copied
    /// shouldn't lose it just because they had something read to them.
    private static var letzteAusloesung = Date.distantPast

    static func vorlesen(mit mund: Sprecher) {
        // Two quick presses should read once, not twice. The second one used
        // to land in the middle of the first one's clipboard dance and read
        // the whole thing over again.
        guard Date().timeIntervalSince(letzteAusloesung) > 1.2 else { return }
        letzteAusloesung = Date()

        let ablage = NSPasteboard.general
        let vorherText = ablage.string(forType: .string)
        let vorherZaehler = ablage.changeCount

        befehlC()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let neu = ablage.changeCount != vorherZaehler
            let text = ablage.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if neu && !text.isEmpty {
                mund.sprich(text)
            } else {
                NSSound(named: "Funk")?.play()   // nothing selected
            }

            // put the clipboard back
            if neu {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    ablage.clearContents()
                    if let vorherText { ablage.setString(vorherText, forType: .string) }
                }
            }
        }
    }

    private static func befehlC() {
        guard let quelle = CGEventSource(stateID: .combinedSessionState) else { return }
        let c: CGKeyCode = 8
        if let ab = CGEvent(keyboardEventSource: quelle, virtualKey: c, keyDown: true) {
            ab.flags = .maskCommand
            ab.post(tap: .cghidEventTap)
        }
        if let auf = CGEvent(keyboardEventSource: quelle, virtualKey: c, keyDown: false) {
            auf.flags = .maskCommand
            auf.post(tap: .cghidEventTap)
        }
    }
}
