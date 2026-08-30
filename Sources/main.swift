// Hark — hands-free dictation for the Mac.
// v0.1: only proves the chain holds — menu bar, icon, state, menu.

import AppKit

@MainActor
final class HarkDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var hoertZu = true
    private var meldung: String?
    private var spracheSchonGefragt = false
    private var schonNeugestartet = false
    private var tastenwaechter: Any?
    private var letzteOhrEinstellung = ""
    private var letzteVorleseDatei = ""
    private var musikWegenDiktat = false
    private var musikWegenSprache = false
    private let ohr = Hoerer()
    private let mund = Sprecher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        baueMenue()
        zeichneSymbol()

        ohr.beiLageWechsel = { [weak self] lage in
            guard let self else { return }
            switch lage {
            case .keineErlaubnis(let grund):
                if grund == "SPRACHE_FEHLT" {
                    self.meldung = T.t("Sprachmodell fehlt", "language model missing")
                    if !self.spracheSchonGefragt {
                        self.spracheSchonGefragt = true
                        Selbsthilfe.spracheAnbieten(
                            Zuhoersprache.aktuell)
                    }
                } else {
                    self.meldung = grund
                }
                self.hoertZu = false
            case .aus:
                self.meldung = nil
            case .wartetAufWeckwort, .nimmtAuf:
                self.meldung = nil
            }

            // Pause the music for exactly as long as we are recording. Hanging
            // it on the state instead of on the wake word and the finished
            // sentence makes it balanced by construction: every way out of
            // recording — an empty sentence, a stop, an error — turns it back
            // on. Before this, one empty sentence left the music off for the
            // rest of the day.
            var nimmtAuf = false
            if case .nimmtAuf = lage { nimmtAuf = true }
            if nimmtAuf != self.musikWegenDiktat {
                self.musikWegenDiktat = nimmtAuf
                if nimmtAuf {
                    Musik.anhalten { pausiert in
                        // A second, higher sound once the music is really off.
                        // Nothing is lost in the meantime — Hark records the
                        // whole time — but waiting for silence that has not
                        // arrived yet is unpleasant, and now you can hear when
                        // it has. Without music the first sound already says it,
                        // so there is no second one.
                        if pausiert { NSSound(named: "Pop")?.play() }
                    }
                } else {
                    Musik.weiter()
                }
            }

            self.menueAuffrischen()
        }

        ohr.beiWeckwort = { [weak self] in
            NSSound(named: "Tink")?.play()
            self?.menueAuffrischen()
        }

        ohr.beiDiktat = { [weak self] satz in
            guard let self else { return }
            guard !satz.isEmpty else { return }
            // Last line of defence: if this is what Hark said itself a moment
            // ago, it is not something you said. Do not type it.
            guard !Sprecher.stammtVonUns(satz) else {
                self.meldung = T.t("eigene Stimme erkannt, nicht getippt",
                                   "own voice recognised, not typed")
                self.menueAuffrischen()
                return
            }
            guard Schreiber.darfTippen else {
                self.meldung = T.t("darf noch nicht tippen", "not allowed to type yet")
                self.menueAuffrischen()
                Schreiber.erlaubnisAnfragen()
                return
            }
            Verlauf.geteilt.merken(satz)
            Schreiber.tippe(satz)
            if UserDefaults.standard.object(forKey: "eingabeDruecken") == nil
                || UserDefaults.standard.bool(forKey: "eingabeDruecken") {
                // wait a moment for the app to digest the text
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    Schreiber.eingabe()
                }
            }
            self.menueAuffrischen()
        }

        mund.beiSprechwechsel = { [weak self] redet in
            guard let self else { return }
            self.ohr.taub = redet
            redet ? Lautstaerke.anheben() : Lautstaerke.zurueck()
            if redet != self.musikWegenSprache {
                self.musikWegenSprache = redet
                redet ? Musik.anhalten() : Musik.weiter()
            }
            self.menueAuffrischen()
        }
        mund.starten()

        // One shortcut that works everywhere: select text, press Option+Command+L.
        tastenwaechter = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return }
            let noetig: NSEvent.ModifierFlags = [.command, .option]
            guard e.modifierFlags.intersection(.deviceIndependentFlagsMask) == noetig,
                  e.charactersIgnoringModifiers?.lowercased() == "l" else { return }
            Task { @MainActor in Auswahl.vorlesen(mit: self.mund) }
        }

        if !WillkommenFenster.schonGesehen {
            let w = WillkommenFenster.geteilt
            w.beiFertig = { [weak self] in
                guard let self else { return }
                self.meldung = nil
                self.ohr.stoppen()
                if self.hoertZu { self.ohr.starten() }
                self.menueAuffrischen()
                // macOS only counts the typing permission after a restart.
                if Schreiber.darfTippen && !self.schonNeugestartet {
                    self.schonNeugestartet = true
                    Selbsthilfe.neustartAnbieten()
                }
            }
            w.zeigen()
        } else if !Schreiber.darfTippen {
            meldung = T.t("braucht noch die Bedienungshilfen", "needs Accessibility permission")
            Schreiber.erlaubnisAnfragen()
        }

        ohr.starten()
    }

    // MARK: - Icon

    private func zeichneSymbol() {
        guard let button = statusItem.button else { return }
        let name: String
        if meldung != nil {
            name = "ear.trianglebadge.exclamationmark"
        } else if mund.redetGerade {
            name = "speaker.wave.2.fill"
        } else if case .nimmtAuf = ohr.lage {
            name = "waveform"
        } else if hoertZu {
            name = "ear.fill"
        } else {
            name = "ear"
        }
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "Hark")
        symbol?.isTemplate = true
        button.image = symbol
        button.toolTip = zustandstext()
    }

    private func zustandstext() -> String {
        if let meldung { return "Hark — \(meldung)" }
        if mund.redetGerade { return T.t("Hark — liest gerade vor", "Hark — reading aloud") }
        if case .nimmtAuf = ohr.lage { return T.t("Hark — ich höre dir zu", "Hark — listening to you") }
        return hoertZu
            ? T.t("Hark — wartet auf „\(ohr.weckwort)“", "Hark — waiting for “\(ohr.weckwort)”")
            : T.t("Hark — pausiert", "Hark — paused")
    }

    // MARK: - Menu

    private func baueMenue() {
        let menu = NSMenu()

        let kopf = NSMenuItem(title: "Hark \(harkVersion)", action: nil, keyEquivalent: "")
        kopf.tag = 0
        kopf.isEnabled = false
        kopf.attributedTitle = NSAttributedString(
            string: "Hark \(harkVersion)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
        menu.addItem(kopf)

        let zustand = NSMenuItem(title: zustandstext(), action: nil, keyEquivalent: "")
        zustand.isEnabled = false
        zustand.tag = 1
        menu.addItem(zustand)

        menu.addItem(.separator())

        let pause = NSMenuItem(title: "",
                               action: #selector(zuhoerenUmschalten),
                               keyEquivalent: "m")
        pause.target = self
        pause.tag = 2
        menu.addItem(pause)

        let musik = NSMenuItem(title: "",
                               action: #selector(musikUmschalten),
                               keyEquivalent: "")
        musik.target = self
        musik.tag = 10
        menu.addItem(musik)

        let verlauf = NSMenuItem(title: "",
                                 action: #selector(verlaufZeigen),
                                 keyEquivalent: "h")
        verlauf.target = self
        verlauf.tag = 9
        menu.addItem(verlauf)

        let lesen = NSMenuItem(title: "",
                               action: #selector(auswahlVorlesen),
                               keyEquivalent: "l")
        lesen.target = self
        lesen.tag = 8
        menu.addItem(lesen)

        let claude = NSMenuItem(title: "",
                                action: #selector(claudeEinrichten),
                                keyEquivalent: "c")
        claude.target = self
        claude.tag = 7
        menu.addItem(claude)

        let ruhe = NSMenuItem(title: "",
                              action: #selector(vorlesenAbbrechen),
                              keyEquivalent: ".")
        ruhe.target = self
        ruhe.tag = 4
        menu.addItem(ruhe)

        menu.addItem(.separator())

        let einst = NSMenuItem(title: "",
                               action: #selector(einstellungenOeffnen),
                               keyEquivalent: ",")
        einst.target = self
        einst.tag = 5
        menu.addItem(einst)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "",
                              action: #selector(beenden),
                              keyEquivalent: "q")
        quit.target = self
        quit.tag = 6
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func menueAuffrischen() {
        guard let menu = statusItem.menu else { return }
        menu.item(withTag: 0)?.title = "Hark \(harkVersion)"
        menu.item(withTag: 1)?.title = zustandstext()
        menu.item(withTag: 2)?.title = hoertZu
            ? T.t("Zuhören pausieren", "Pause listening")
            : T.t("Zuhören fortsetzen", "Resume listening")
        menu.item(withTag: 10)?.title = Musik.eingeschaltet
            ? T.t("Musik anhalten: an", "Pause music: on")
            : T.t("Musik anhalten: aus", "Pause music: off")
        menu.item(withTag: 10)?.state = Musik.eingeschaltet ? .on : .off
        menu.item(withTag: 9)?.title = T.t("Verlauf…", "History…")
        menu.item(withTag: 8)?.title = T.t("Markiertes vorlesen  ⌥⌘L", "Read selection  ⌥⌘L")
        menu.item(withTag: 7)?.title = T.t("Für Claude einrichten…", "Set up for Claude…")
        menu.item(withTag: 4)?.title = T.t("Vorlesen abbrechen", "Stop reading")
        menu.item(withTag: 5)?.title = T.t("Einstellungen…", "Settings…")
        menu.item(withTag: 6)?.title = T.t("Hark beenden", "Quit Hark")
        zeichneSymbol()
    }

    // MARK: - Actions

    @objc private func zuhoerenUmschalten() {
        hoertZu.toggle()
        hoertZu ? ohr.starten() : ohr.stoppen()
        menueAuffrischen()
    }

    @objc private func musikUmschalten() {
        Musik.eingeschaltet.toggle()
        if !Musik.eingeschaltet { Musik.aufloesen() }
        menueAuffrischen()
    }

    @objc private func verlaufZeigen() {
        Verlauf.geteilt.zeigen()
    }

    @objc private func auswahlVorlesen() {
        Auswahl.vorlesen(mit: mund)
    }

    @objc private func claudeEinrichten() {
        Selbsthilfe.claudeAnleitungKopieren()
    }

    @objc private func vorlesenAbbrechen() {
        mund.abbrechen()
        menueAuffrischen()
    }

    @objc private func einstellungenOeffnen() {
        let fenster = EinstellungenFenster.geteilt
        fenster.beiAenderung = { [weak self] in
            guard let self else { return }
            // Only rebuild the listener when something it actually depends on
            // changed. Restarting the microphone on every sidebar click was
            // both wasteful and, with two starts overlapping, a crash.
            let d = UserDefaults.standard
            let jetzt = "\(d.string(forKey: "weckwort") ?? "")|\(d.string(forKey: "sprache") ?? "")"
            if jetzt != self.letzteOhrEinstellung {
                self.letzteOhrEinstellung = jetzt
                self.ohr.stoppen()
                if self.hoertZu { self.ohr.starten() }
            }
            let datei = d.string(forKey: "vorleseDatei") ?? ""
            if datei != self.letzteVorleseDatei {
                self.letzteVorleseDatei = datei
                self.mund.stoppen()
                self.mund.starten()
            }
            self.menueAuffrischen()   // also picks up a changed interface language
        }
        fenster.zeigen()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Whatever we paused would otherwise stay paused: the app is gone and
        // nobody is left to press play.
        Musik.sofortAufloesen()
    }

    @objc private func beenden() {
        NSApp.terminate(nil)
    }
}

// Swift 6 won't allow main-actor calls directly at program start.
// But at startup we are demonstrably on the main thread — so we say
// so to the compiler in as many words. The delegate is global because
// NSApplication only holds it weakly and would bin it right away.

nonisolated(unsafe) var harkDelegate: HarkDelegate?

MainActor.assumeIsolated {
    let d = HarkDelegate()
    harkDelegate = d

    let app = NSApplication.shared
    app.delegate = d
    app.setActivationPolicy(.accessory)   // no Dock icon, no window
    app.run()
}
