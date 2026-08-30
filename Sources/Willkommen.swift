// Willkommen.swift — the first launch.
//
// A stranger opening Hark for the first time otherwise sees only an ear
// in the menu bar and three system prompts out of nowhere. This window
// explains beforehand what is about to happen, and why.

import AppKit
import AVFoundation
import Speech
import ApplicationServices

@MainActor
final class WillkommenFenster: NSObject, NSWindowDelegate {

    static let geteilt = WillkommenFenster()
    var beiFertig: (() -> Void)?

    private var fenster: NSWindow?
    private var mikroZeile: NSTextField!
    private var spracheZeile: NSTextField!
    private var tastenZeile: NSTextField!
    private var weiterKnopf: NSButton!
    private var uhr: Timer?

    static var schonGesehen: Bool {
        get { UserDefaults.standard.bool(forKey: "willkommenGesehen") }
        set { UserDefaults.standard.set(newValue, forKey: "willkommenGesehen") }
    }

    func zeigen() {
        if let fenster {
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            return
        }
        let f = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 430),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        f.title = T.t("Willkommen bei Hark", "Welcome to Hark")
        f.isReleasedWhenClosed = false
        f.center()
        f.delegate = self
        f.contentView = inhalt()
        fenster = f
        NSApp.activate(ignoringOtherApps: true)
        f.makeKeyAndOrderFront(nil)

        uhr = Timer.harkUhr(1.0, wiederholt: true) { [weak self] _ in
            Task { @MainActor in self?.standAuffrischen() }
        }
    }

    func windowWillClose(_ n: Notification) {
        uhr?.invalidate(); uhr = nil
        fenster = nil
        Self.schonGesehen = true
        beiFertig?()
    }

    private func inhalt() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 430))
        var y: CGFloat = 380

        let titel = NSTextField(labelWithString: T.t("Freihändig arbeiten", "Hands-free, out loud"))
        titel.frame = NSRect(x: 30, y: y, width: 420, height: 28)
        titel.font = .systemFont(ofSize: 20, weight: .semibold)
        v.addSubview(titel)

        y -= 46
        let text = NSTextField(wrappingLabelWithString: T.t("""
        Sag „hey hark“, rede weiter, und Hark tippt es dort hin, wo dein Cursor steht. \
        Antworten liest sie dir vor. Alles bleibt auf diesem Mac — ins Netz geht nur, was du in den Einstellungen ausdrücklich erlaubst.

        Dafür braucht sie drei Erlaubnisse. macOS fragt dich gleich danach:
        """, """
        Say “hey hark”, keep talking, and Hark types it wherever your cursor is. \
        It reads answers back to you. Everything stays on this Mac — nothing goes online unless you switch it on yourself.

        For that it needs three permissions. macOS will ask you now:
        """))
        text.frame = NSRect(x: 30, y: y - 40, width: 420, height: 86)
        text.font = .systemFont(ofSize: 12)
        text.textColor = .secondaryLabelColor
        v.addSubview(text)

        y -= 78
        func zeile(_ titel: String, _ erklaerung: String) -> NSTextField {
            let l = NSTextField(wrappingLabelWithString: "")
            l.frame = NSRect(x: 30, y: y - 26, width: 420, height: 34)
            l.font = .systemFont(ofSize: 12)
            v.addSubview(l)
            let e = NSTextField(labelWithString: erklaerung)
            e.frame = NSRect(x: 52, y: y - 42, width: 400, height: 16)
            e.font = .systemFont(ofSize: 10)
            e.textColor = .tertiaryLabelColor
            v.addSubview(e)
            y -= 54
            return l
        }
        mikroZeile = zeile("", T.t("um dein Weckwort zu hören", "to hear your wake word"))
        spracheZeile = zeile("", T.t("um zu verstehen, was du sagst — auf dem Gerät",
                                     "to understand you — on device"))
        tastenZeile = zeile("", T.t("um den Text in andere Programme zu tippen",
                                    "to type the text into other apps"))

        weiterKnopf = NSButton(title: T.t("Erlaubnisse erteilen", "Grant permissions"),
                               target: self, action: #selector(erlaubnisse))
        weiterKnopf.frame = NSRect(x: 274, y: 24, width: 176, height: 32)
        weiterKnopf.bezelStyle = .rounded
        weiterKnopf.keyEquivalent = "\r"
        v.addSubview(weiterKnopf)

        let claudeHinweis = NSTextField(wrappingLabelWithString: T.t(
            "Du nutzt Claude? Dann findest du im Menü „Für Claude einrichten“ — damit liest Hark dir Claudes Antworten vor. Das musst du in jedem neuen Chat einmal machen.",
            "Using Claude? The menu has “Set up for Claude” — that makes Hark read Claude’s answers aloud. Do it once in every new chat."))
        claudeHinweis.frame = NSRect(x: 30, y: 64, width: 420, height: 32)
        claudeHinweis.font = .systemFont(ofSize: 10)
        claudeHinweis.textColor = .tertiaryLabelColor
        v.addSubview(claudeHinweis)

        let spaeter = NSButton(title: T.t("Später", "Later"), target: self,
                               action: #selector(schliessen))
        spaeter.frame = NSRect(x: 186, y: 24, width: 80, height: 32)
        spaeter.bezelStyle = .rounded
        v.addSubview(spaeter)

        standAuffrischen()
        return v
    }

    private func standAuffrischen() {
        let mikro = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let sprache = SFSpeechRecognizer.authorizationStatus() == .authorized
        let tasten = AXIsProcessTrusted()

        func male(_ feld: NSTextField?, _ ok: Bool, _ name: String) {
            let zeichen = ok ? "✓" : "○"
            let farbe: NSColor = ok ? .systemGreen : .secondaryLabelColor
            let a = NSMutableAttributedString(string: "\(zeichen)  \(name)")
            a.addAttribute(.foregroundColor, value: farbe, range: NSRange(location: 0, length: 1))
            feld?.attributedStringValue = a
        }
        male(mikroZeile, mikro, T.t("Mikrofon", "Microphone"))
        male(spracheZeile, sprache, T.t("Spracherkennung", "Speech recognition"))
        male(tastenZeile, tasten, T.t("Bedienungshilfen", "Accessibility"))

        if mikro && sprache && tasten {
            weiterKnopf.title = T.t("Los geht’s", "Let’s go")
            weiterKnopf.action = #selector(schliessen)
        }
    }

    @objc private func erlaubnisse() {
        SFSpeechRecognizer.requestAuthorization { _ in
            Task { @MainActor in
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    Task { @MainActor in
                        if !AXIsProcessTrusted() { Schreiber.erlaubnisAnfragen() }
                        self.standAuffrischen()
                    }
                }
            }
        }
    }

    @objc private func schliessen() { fenster?.performClose(nil) }
}
