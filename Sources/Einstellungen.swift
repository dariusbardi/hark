// Einstellungen.swift — wake word, language, voice, dictation and Piper.

import AppKit
import AVFoundation
import Speech

let harkVersion = "1.3.1"

@MainActor
final class EinstellungenFenster: NSObject, NSWindowDelegate,
                                  NSTableViewDataSource, NSTableViewDelegate {

    static let geteilt = EinstellungenFenster()
    var beiAenderung: (() -> Void)?

    private var fenster: NSWindow?
    private var weckwortFeld: NSTextField!
    private var sprachWahl: NSPopUpButton!
    private var oberflaecheWahl: NSPopUpButton!
    private var stimmWahl: NSPopUpButton!
    private var tempoRegler: NSSlider!
    private var lautRegler: NSSlider!
    private var lautWert: NSTextField!
    private var pausenFeld: NSTextField!
    private var eingabeHaken: NSButton!
    private var mittippenHaken: NSButton!
    private var woerterFeld: NSTextView!
    private var serverHaken: NSButton!
    private var autostartHaken: NSButton!
    private var dateiFeld: NSTextField!

    private var motorText: NSTextField!
    private var motorKnopf: NSButton!
    private var klangWahl: NSPopUpButton!
    private var klangKnopf: NSButton!
    private var balken: NSProgressIndicator!
    private var balkenText: NSTextField!

    private let sprecher = AVSpeechSynthesizer()
    private let piperProbe = PiperStimme()

    /// Which languages can this Mac actually understand?
    ///
    /// There used to be a hand-written list here. That was guesswork twice
    /// over: it named languages this machine may not support, and it silently
    /// omitted ones it does. Now we ask the system and show its answer —
    /// always correct, and it grows on its own with macOS.
    private lazy var sprachen: [(String, String)] = {
        let eigene = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        let anzeige = Locale(identifier: T.istDeutsch ? "de" : "en")

        func name(_ kennung: String) -> String {
            let kurz = String(kennung.prefix(2))
            let sprache = anzeige.localizedString(forLanguageCode: kurz) ?? kennung
            let region = kennung.split(separator: "-").last.map(String.init) ?? ""
            let land = anzeige.localizedString(forRegionCode: region) ?? region
            return "\(sprache.prefix(1).uppercased())\(sprache.dropFirst()) (\(land))"
        }

        var paare = SFSpeechRecognizer.supportedLocales()
            .map { $0.identifier.replacingOccurrences(of: "_", with: "-") }
            .filter { $0.contains("-") }
            .map { (name($0), $0) }

        paare.sort { a, b in
            // this Mac's own language first, then English, then alphabetical
            let ra = a.1 == eigene ? 0 : (a.1.hasPrefix("en") ? 1 : 2)
            let rb = b.1 == eigene ? 0 : (b.1.hasPrefix("en") ? 1 : 2)
            return ra == rb ? a.0 < b.0 : ra < rb
        }
        return paare.isEmpty
            ? [("Deutsch (Deutschland)", "de-DE"), ("English (United States)", "en-US")]
            : paare
    }()

    // MARK: - Window

    func zeigen() {
        if let fenster {
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            return
        }
        let f = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        f.title = "Hark — \(T.t("Einstellungen", "Settings"))"
        f.isReleasedWhenClosed = false
        f.center()
        f.delegate = self
        f.contentView = baueInhalt()
        fenster = f
        NSApp.activate(ignoringOtherApps: true)
        f.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ n: Notification) { sichern(); fenster = nil }

    // MARK: - Layout

    private var feld: NSView!
    private var y: CGFloat = 0
    private var seitenleiste: NSTableView?
    private var buehne: NSView?
    private var seiten: [(String, () -> NSView)] = []

    private func ueberschrift(_ text: String) {
        y -= 4
        let l = NSTextField(labelWithString: text)
        l.frame = NSRect(x: 24, y: y, width: 420, height: 22)
        l.font = .systemFont(ofSize: 15, weight: .semibold)
        feld.addSubview(l)
        y -= 12
    }

    private func zeile(_ text: String) {
        let l = NSTextField(labelWithString: text)
        l.frame = NSRect(x: 24, y: y, width: 140, height: 20)
        l.alignment = .right
        l.textColor = .secondaryLabelColor
        feld.addSubview(l)
    }

    /// A free-standing paragraph across the full width. Returns how much
    /// vertical space it took, so the caller can move on by exactly that.
    @discardableResult
    private func blockText(_ text: String, in v: NSView,
                           x: CGFloat = 24, klein: Bool = false) -> CGFloat {
        let breite = 500 - x
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: klein ? 10 : 11)
        l.textColor = klein ? .tertiaryLabelColor : .secondaryLabelColor
        l.preferredMaxLayoutWidth = breite
        let hoehe = ceil(l.sizeThatFits(NSSize(width: breite,
                                               height: .greatestFiniteMagnitude)).height)
        l.frame = NSRect(x: x, y: y - hoehe, width: breite, height: hoehe)
        v.addSubview(l)
        return hoehe + 10
    }

    /// A note under a control.
    ///
    /// The first version assumed a fixed height of two lines. Anything longer
    /// spilled over the control below it — which is exactly what a settings
    /// window must never do. Now the text is measured and the cursor moves by
    /// however much it actually needs.
    private func notiz(_ text: String, breite: CGFloat = 316) {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 10)
        l.textColor = .tertiaryLabelColor
        l.preferredMaxLayoutWidth = breite
        let hoehe = ceil(l.sizeThatFits(NSSize(width: breite,
                                               height: .greatestFiniteMagnitude)).height)
        y -= (hoehe + 6)
        l.frame = NSRect(x: 176, y: y, width: breite, height: hoehe)
        feld.addSubview(l)
        y -= 12
    }

    /// A fresh page for the right-hand side. Every section gets its own,
    /// so nothing has to be squeezed into a scroller any more.
    private func seiteBeginnen() -> NSView {
        feld = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 400))
        y = 366
        return feld
    }

    private func baueInhalt() -> NSView {
        seiten = [
            (T.t("Allgemein", "General"),        { [unowned self] in self.seiteAllgemein() }),
            (T.t("Weckruf", "Wake word"),        { [unowned self] in self.seiteWeckruf() }),
            (T.t("Stimme", "Voice"),             { [unowned self] in self.seiteStimme() }),
            (T.t("Diktat", "Dictation"),         { [unowned self] in self.seiteDiktat() }),
            (T.t("Erkennung", "Accuracy"),       { [unowned self] in self.seiteErkennung() }),
            (T.t("Vorlesen", "Read aloud"),      { [unowned self] in self.seiteVorlesen() }),
            (T.t("Piper", "Piper"),              { [unowned self] in self.seitePiper() }),
            (T.t("Über Hark", "About Hark"),     { [unowned self] in self.seiteUeber() }),
        ]

        let aussen = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 460))

        // --- sidebar ---
        let leisteRollen = NSScrollView(frame: NSRect(x: 0, y: 0, width: 176, height: 460))
        leisteRollen.drawsBackground = false
        leisteRollen.autoresizingMask = [.height]
        let leiste = NSTableView(frame: leisteRollen.bounds)
        leiste.headerView = nil
        leiste.rowHeight = 30
        leiste.style = .sourceList
        leiste.backgroundColor = .clear
        leiste.dataSource = self
        leiste.delegate = self
        let spalte = NSTableColumn(identifier: .init("titel"))
        spalte.width = 160
        leiste.addTableColumn(spalte)
        leisteRollen.documentView = leiste
        seitenleiste = leiste
        aussen.addSubview(leisteRollen)

        let trenner = NSBox(frame: NSRect(x: 176, y: 0, width: 1, height: 460))
        trenner.boxType = .separator
        trenner.autoresizingMask = [.height]
        aussen.addSubview(trenner)

        // --- stage ---
        let stelle = NSView(frame: NSRect(x: 177, y: 52, width: 543, height: 408))
        stelle.autoresizingMask = [.width, .height]
        buehne = stelle
        aussen.addSubview(stelle)

        let strich = NSBox(frame: NSRect(x: 177, y: 51, width: 543, height: 1))
        strich.boxType = .separator
        strich.autoresizingMask = [.width]
        aussen.addSubview(strich)

        let sichernKnopf = NSButton(title: T.t("Sichern", "Save"), target: self,
                                    action: #selector(sichernUndSchliessen))
        sichernKnopf.frame = NSRect(x: 604, y: 11, width: 96, height: 30)
        sichernKnopf.bezelStyle = .rounded
        sichernKnopf.keyEquivalent = "\r"
        sichernKnopf.autoresizingMask = [.minXMargin]
        aussen.addSubview(sichernKnopf)

        leiste.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        seiteZeigen(0)
        return aussen
    }

    private func seiteZeigen(_ index: Int) {
        guard let buehne, index < seiten.count else { return }
        buehne.subviews.forEach { $0.removeFromSuperview() }
        // The old page's controls are gone — forget them, or the next save
        // would read values from views that no longer exist.
        weckwortFeld = nil; sprachWahl = nil; oberflaecheWahl = nil; mittippenHaken = nil; woerterFeld = nil; serverHaken = nil; stimmWahl = nil; tempoRegler = nil; lautRegler = nil; lautWert = nil
        pausenFeld = nil; eingabeHaken = nil; autostartHaken = nil; dateiFeld = nil
        motorText = nil; motorKnopf = nil; klangWahl = nil; klangKnopf = nil
        balken = nil; balkenText = nil
        let inhalt = seiten[index].1()
        inhalt.frame = NSRect(x: 0, y: buehne.bounds.height - 400,
                              width: buehne.bounds.width, height: 400)
        inhalt.autoresizingMask = [.width, .minYMargin]
        buehne.addSubview(inhalt)
    }

    // MARK: - The pages

    private func seiteAllgemein() -> NSView {
        let v = seiteBeginnen()
        ueberschrift(T.t("Allgemein", "General"))
        y -= 30
        zeile(T.t("Oberfläche", "Interface"))
        oberflaecheWahl = NSPopUpButton(frame: NSRect(x: 174, y: y - 4, width: 302, height: 26))
        oberflaecheWahl.addItems(withTitles: [
            T.t("automatisch (wie das System)", "automatic (follow system)"),
            "Deutsch", "English"])
        switch T.eingestellt {
        case "de": oberflaecheWahl.selectItem(at: 1)
        case "en": oberflaecheWahl.selectItem(at: 2)
        default:   oberflaecheWahl.selectItem(at: 0)
        }
        oberflaecheWahl.target = self
        oberflaecheWahl.action = #selector(oberflaecheGewechselt)
        v.addSubview(oberflaecheWahl)
        notiz(T.t("Die Sprache von Hark selbst. Beim Umstellen baut sich das Fenster neu auf.",
                  "Hark’s own language. Switching rebuilds this window."))

        y -= 30
        autostartHaken = NSButton(checkboxWithTitle: T.t("Hark beim Anmelden starten",
                                                          "Start Hark at login"),
                                  target: self, action: #selector(autostartUmschalten))
        autostartHaken.frame = NSRect(x: 174, y: y, width: 320, height: 20)
        autostartHaken.state = Autostart.an ? .on : .off
        v.addSubview(autostartHaken)

        y -= 30
        let updateHaken = NSButton(checkboxWithTitle: T.t("Nach neuen Fassungen schauen",
                                                          "Check for new versions"),
                                   target: self, action: #selector(updatePruefenUmschalten))
        updateHaken.frame = NSRect(x: 174, y: y, width: 340, height: 20)
        updateHaken.state = Neuigkeit.eingeschaltet ? .on : .off
        v.addSubview(updateHaken)
        notiz(T.t("Einmal am Tag eine Frage an GitHub, sonst nichts. Hark sagt dir nur Bescheid und tauscht sich nie von allein aus. Das ist die einzige Stelle, an der Hark ins Netz geht — deshalb ist sie standardmäßig aus.",
                  "One question to GitHub a day, nothing else. Hark only tells you; it never replaces itself. This is the only place Hark goes online, which is why it starts switched off."))

        y -= 34
        let musikHaken = NSButton(checkboxWithTitle: T.t("Musik anhalten, während Hark hört oder spricht",
                                                          "Pause music while Hark listens or speaks"),
                                  target: self, action: #selector(musikUmschalten))
        musikHaken.frame = NSRect(x: 174, y: y, width: 340, height: 20)
        musikHaken.state = Musik.eingeschaltet ? .on : .off
        v.addSubview(musikHaken)
        notiz(T.t("Gilt für Music und Spotify. Browser-Musik bleibt an.",
                  "Music and Spotify only. Browser audio keeps playing."))
        return v
    }

    private func seiteWeckruf() -> NSView {
        let v = seiteBeginnen()
        ueberschrift(T.t("Weckruf", "Wake word"))
        y -= 30
        zeile(T.t("Weckruf", "Wake word"))
        weckwortFeld = NSTextField(frame: NSRect(x: 176, y: y - 3, width: 300, height: 24))
        weckwortFeld.stringValue = UserDefaults.standard.string(forKey: "weckwort") ?? "hey hark"
        weckwortFeld.placeholderString = "hey hark"
        v.addSubview(weckwortFeld)
        notiz(T.t("Zwei Silben klappen am besten. „hey jarvis“ geht genauso.",
                  "Two syllables work best. “hey jarvis” is fine too."))

        y -= 26
        zeile(T.t("Zuhören in", "Listen in"))
        sprachWahl = NSPopUpButton(frame: NSRect(x: 174, y: y - 4, width: 302, height: 26))
        sprachWahl.addItems(withTitles: sprachen.map(\.0))
        let jetzige = Zuhoersprache.aktuell
        if let i = sprachen.firstIndex(where: { $0.1 == jetzige }) { sprachWahl.selectItem(at: i) }
        sprachWahl.target = self
        sprachWahl.action = #selector(spracheGewechselt)
        v.addSubview(sprachWahl)
        notiz(T.t("Nur eine Sprache gleichzeitig — das ist Apples Grenze. Die Liste kommt von deinem Mac.",
                  "One language at a time — Apple’s limit, not ours. The list comes from your Mac."))
        y -= 30
        mittippenHaken = NSButton(checkboxWithTitle: T.t("Weckruf mittippen",
                                                          "type the wake word too"),
                                  target: nil, action: nil)
        mittippenHaken.frame = NSRect(x: 174, y: y, width: 320, height: 20)
        mittippenHaken.state = UserDefaults.standard.bool(forKey: "weckwortMittippen") ? .on : .off
        v.addSubview(mittippenHaken)
        notiz(T.t("Bleibt er stehen, sieht der Empfänger: gesprochen, nicht getippt.",
                  "Left in, it shows the reader: spoken, not typed."))
        return v
    }

    private func seiteStimme() -> NSView {
        let v = seiteBeginnen()
        ueberschrift(T.t("Stimme", "Voice"))
        y -= 30
        zeile(T.t("Vorlesen mit", "Speak with"))
        stimmWahl = NSPopUpButton(frame: NSRect(x: 174, y: y - 4, width: 216, height: 26))
        v.addSubview(stimmWahl)
        let probe = NSButton(title: T.t("Probe", "Preview"), target: self,
                             action: #selector(probeHoeren))
        probe.frame = NSRect(x: 398, y: y - 5, width: 80, height: 28)
        probe.bezelStyle = .rounded
        v.addSubview(probe)

        y -= 30
        let sprachHaken = NSButton(checkboxWithTitle: T.t("Stimme zur Sprache des Textes wählen",
                                                          "Match the voice to the text’s language"),
                                   target: self, action: #selector(stimmeNachSpracheUmschalten))
        sprachHaken.frame = NSRect(x: 174, y: y, width: 340, height: 20)
        sprachHaken.state = Sprecher.stimmeNachSprache ? .on : .off
        v.addSubview(sprachHaken)
        notiz(T.t("Kommt eine Antwort auf Englisch, während oben eine deutsche Stimme steht, klingt das furchtbar. Hark schaut sich den Text an und nimmt eine passende Stimme. Erkennt es die Sprache nicht sicher, bleibt es bei deiner.",
                  "An English answer read by a German voice is barely words. Hark looks at the text and picks a voice that fits. If it cannot tell for sure, it keeps yours."))

        y -= 36
        zeile(T.t("Tempo", "Speed"))   // applies to Apple voices and Piper alike
        tempoRegler = NSSlider(frame: NSRect(x: 174, y: y - 2, width: 216, height: 24))
        tempoRegler.minValue = 0.35
        tempoRegler.maxValue = 0.62
        let gemerkt = UserDefaults.standard.double(forKey: "sprechtempo")
        tempoRegler.doubleValue = gemerkt > 0.1 ? gemerkt : 0.48
        tempoRegler.target = self
        tempoRegler.action = #selector(tempoGeaendert)
        v.addSubview(tempoRegler)

        y -= 40
        let apple = NSButton(title: T.t("Apple-Stimmen laden…", "Get Apple voices…"),
                             target: self, action: #selector(stimmenLadenOeffnen))
        apple.frame = NSRect(x: 174, y: y, width: 180, height: 28)
        apple.bezelStyle = .rounded
        v.addSubview(apple)
        let eigene = NSButton(title: T.t("Eigene Stimme…", "Personal Voice…"),
                              target: self, action: #selector(eigeneStimmeErklaeren))
        eigene.frame = NSRect(x: 362, y: y, width: 150, height: 28)
        eigene.bezelStyle = .rounded
        v.addSubview(eigene)

        y -= 14
        notiz(T.t("Apples bessere Stimmen sind gratis, nur nicht vorinstalliert. Die eigene nimmt dein Mac von dir auf.",
                  "Apple’s better voices are free, just not preinstalled. Personal Voice records your own."), breite: 316)

        stimmenLaden()
        eigeneStimmeAnfragen()
        return v
    }

    private func seiteDiktat() -> NSView {
        let v = seiteBeginnen()
        ueberschrift(T.t("Diktat", "Dictation"))
        y -= 30
        zeile(T.t("Pause bis Schluss", "Pause to finish"))
        pausenFeld = NSTextField(frame: NSRect(x: 176, y: y - 3, width: 58, height: 24))
        let p = UserDefaults.standard.double(forKey: "stillePause")
        pausenFeld.stringValue = String(format: "%.1f", p > 0.4 ? p : 1.8)
        v.addSubview(pausenFeld)
        let sek = NSTextField(labelWithString: T.t("Sekunden Ruhe beenden den Satz",
                                                   "seconds of silence end the sentence"))
        sek.frame = NSRect(x: 242, y: y + 1, width: 260, height: 18)
        sek.font = .systemFont(ofSize: 11)
        sek.textColor = .tertiaryLabelColor
        v.addSubview(sek)
        notiz(T.t("Unterbricht Hark dich mitten im Satz? Wert hochdrehen.",
                  "Hark cutting you off mid-sentence? Raise it."))

        y -= 26
        eingabeHaken = NSButton(checkboxWithTitle: T.t("danach die Eingabetaste drücken",
                                                       "press Return afterwards"),
                                target: nil, action: nil)
        eingabeHaken.frame = NSRect(x: 174, y: y, width: 320, height: 20)
        let gesetzt = UserDefaults.standard.object(forKey: "eingabeDruecken") == nil
            ? true : UserDefaults.standard.bool(forKey: "eingabeDruecken")
        eingabeHaken.state = gesetzt ? .on : .off
        v.addSubview(eingabeHaken)

        return v
    }

    private func seiteErkennung() -> NSView {
        let v = seiteBeginnen()
        ueberschrift(T.t("Erkennung verbessern", "Improving accuracy"))

        y -= 24
        y -= blockText(T.t(
            "Wörter, die Hark regelmäßig verhört: Namen, Projekte, Fachbegriffe. Mit Komma oder Zeilenumbruch trennen. Das ist der wirksamste Hebel überhaupt.",
            "Words Hark keeps mishearing: names, projects, jargon. Separate with commas or line breaks. The strongest lever there is."), in: v)
        let rollen = NSScrollView(frame: NSRect(x: 24, y: y - 74, width: 470, height: 84))
        rollen.hasVerticalScroller = true
        rollen.borderType = .bezelBorder
        woerterFeld = NSTextView(frame: rollen.bounds)
        woerterFeld.isRichText = false
        woerterFeld.font = .systemFont(ofSize: 12)
        woerterFeld.string = UserDefaults.standard.string(forKey: "eigeneWoerter") ?? ""
        rollen.documentView = woerterFeld
        v.addSubview(rollen)

        y -= 110
        serverHaken = NSButton(checkboxWithTitle: T.t("Bessere Erkennung über Apples Server",
                                                       "Better accuracy via Apple’s servers"),
                               target: nil, action: nil)
        serverHaken.frame = NSRect(x: 24, y: y, width: 400, height: 20)
        serverHaken.state = UserDefaults.standard.bool(forKey: "serverErkennung") ? .on : .off
        v.addSubview(serverHaken)

        y -= 20
        y -= 6
        y -= blockText(T.t(
            "Treffsicherer — aber deine Sprache verlässt dann den Mac und geht an Apple. Sonst bleibt alles hier.",
            "More accurate — but your speech then leaves the Mac and goes to Apple. Otherwise nothing does."), in: v, x: 42, klein: true)

        return v
    }

    private func seiteVorlesen() -> NSView {
        let v = seiteBeginnen()
        ueberschrift(T.t("Vorlesen von außen", "Read aloud from elsewhere"))
        y -= 26
        y -= blockText(T.t(
            "Was in diese Datei geschrieben wird, liest Hark sofort vor. So kann jedes Programm durch Hark sprechen.",
            "Whatever gets written into this file, Hark reads aloud at once. Any program can speak through Hark."), in: v)
        dateiFeld = NSTextField(labelWithString: "")
        dateiFeld.frame = NSRect(x: 24, y: y, width: 330, height: 18)
        dateiFeld.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        dateiFeld.lineBreakMode = .byTruncatingMiddle
        v.addSubview(dateiFeld)
        let zeigen = NSButton(title: T.t("zeigen", "reveal"), target: self,
                              action: #selector(dateiZeigen))
        zeigen.frame = NSRect(x: 362, y: y - 6, width: 68, height: 26)
        zeigen.bezelStyle = .rounded
        v.addSubview(zeigen)
        let waehlen = NSButton(title: "…", target: self, action: #selector(dateiWaehlen))
        waehlen.frame = NSRect(x: 436, y: y - 6, width: 40, height: 26)
        waehlen.bezelStyle = .rounded
        v.addSubview(waehlen)

        y -= 40
        zeile(T.t("Lautstärke", "Volume"))
        lautRegler = NSSlider(frame: NSRect(x: 174, y: y - 2, width: 196, height: 24))
        lautRegler.minValue = 0
        lautRegler.maxValue = 100
        lautRegler.doubleValue = Double(Lautstaerke.ziel)
        lautRegler.target = self
        lautRegler.action = #selector(lautGeaendert)
        v.addSubview(lautRegler)
        lautWert = NSTextField(labelWithString: "")
        lautWert.frame = NSRect(x: 378, y: y, width: 118, height: 20)
        lautWert.font = .systemFont(ofSize: 11)
        lautWert.textColor = .secondaryLabelColor
        v.addSubview(lautWert)
        lautStandZeigen()

        y -= 8
        y -= blockText(T.t(
            "Hark kann nie lauter sein als der Mac selbst. Damit du ihn über leiser Musik hörst, dreht er den Mac fürs Vorlesen hoch und danach wieder genau dorthin zurück, wo er war. Ganz links heißt: nichts anfassen.",
            "Hark can never be louder than the Mac itself. So it turns the Mac up while it speaks and afterwards puts it back exactly where it was. Far left means: leave the volume alone."), in: v)

        y -= 20
        let claudeKnopf = NSButton(title: T.t("Anleitung für Claude kopieren",
                                              "Copy the instructions for Claude"),
                                   target: self, action: #selector(claudeAnleitung))
        claudeKnopf.frame = NSRect(x: 22, y: y, width: 250, height: 28)
        claudeKnopf.bezelStyle = .rounded
        v.addSubview(claudeKnopf)

        y -= 12
        let cn = NSTextField(wrappingLabelWithString: T.t(
            "Einmal in deinen Chat einfügen — in jeden neuen wieder. Claude braucht dafür Zugriff auf deine Dateien. Im Browser geht es nicht: dort markierst du die Antwort und drückst ⌥⌘L.",
            "Paste it into your chat once — and again in every new one. Claude needs file access for this. In a browser it will not work: select the answer and press ⌥⌘L instead."))
        cn.frame = NSRect(x: 24, y: y - 46, width: 470, height: 46)
        cn.font = .systemFont(ofSize: 10)
        cn.textColor = .tertiaryLabelColor
        v.addSubview(cn)

        dateiStandZeigen()
        return v
    }

    private func seitePiper() -> NSView {
        let v = seiteBeginnen()
        ueberschrift(T.t("Piper — neuronale Stimmen, offline",
                         "Piper — neural voices, offline"))
        y -= 26
        motorText = NSTextField(labelWithString: "")
        motorText.frame = NSRect(x: 24, y: y, width: 340, height: 18)
        motorText.font = .systemFont(ofSize: 12)
        v.addSubview(motorText)
        motorKnopf = NSButton(title: "", target: self, action: #selector(motorKnopfGedrueckt))
        motorKnopf.frame = NSRect(x: 370, y: y - 5, width: 120, height: 28)
        motorKnopf.bezelStyle = .rounded
        v.addSubview(motorKnopf)

        y -= 44
        zeile(T.t("Stimme", "Voice"))
        klangWahl = NSPopUpButton(frame: NSRect(x: 174, y: y - 4, width: 216, height: 26))
        klangWahl.target = self
        klangWahl.action = #selector(klangGewechselt)
        v.addSubview(klangWahl)
        klangKnopf = NSButton(title: "", target: self, action: #selector(klangKnopfGedrueckt))
        klangKnopf.frame = NSRect(x: 398, y: y - 5, width: 92, height: 28)
        klangKnopf.bezelStyle = .rounded
        v.addSubview(klangKnopf)

        y -= 32
        balken = NSProgressIndicator(frame: NSRect(x: 176, y: y, width: 314, height: 12))
        balken.isIndeterminate = false
        balken.minValue = 0; balken.maxValue = 1
        balken.isHidden = true
        v.addSubview(balken)

        y -= 22
        balkenText = NSTextField(wrappingLabelWithString: "")
        balkenText.frame = NSRect(x: 176, y: y - 14, width: 314, height: 30)
        balkenText.font = .systemFont(ofSize: 10)
        balkenText.textColor = .tertiaryLabelColor
        v.addSubview(balkenText)

        katalogLaden()
        motorStandZeigen()
        return v
    }

    private func seiteUeber() -> NSView {
        let v = seiteBeginnen()
        ueberschrift("Hark \(harkVersion)")
        y -= 30
        let text = NSTextField(wrappingLabelWithString: T.t("""
        Sag dein Weckwort, red weiter, und Hark tippt es dorthin, wo dein Cursor steht. Antworten liest es dir vor.

        Alles läuft auf diesem Mac. Die Spracherkennung arbeitet auf dem Gerät — fehlt das Sprachmodell, hört Hark lieber gar nicht zu, statt heimlich ins Netz zu funken. Zwei Ausnahmen gibt es, und beide legst du selbst um: „Apples Server nutzen“ unter Erkennung, und „Nach neuen Fassungen schauen“ unter Allgemein — eine Frage am Tag an GitHub, sonst nichts. Einen Server von uns gibt es nicht, kein Konto, keine Statistik.

        Von Darius Bardi. MIT-Lizenz.
        """, """
        Say your wake word, keep talking, and Hark types it wherever your cursor is. It reads answers back to you.

        Everything runs on this Mac. Speech recognition works on the device — if the language model is missing, Hark refuses to listen rather than quietly going online. There are two exceptions, and both are yours to flip: “use Apple’s servers” under Accuracy, and “check for new versions” under General — one question a day to GitHub, nothing more. No server of ours, no account, no analytics.

        By Darius Bardi. MIT licensed.
        """))
        text.frame = NSRect(x: 24, y: y - 190, width: 470, height: 220)
        text.font = .systemFont(ofSize: 12)
        text.textColor = .secondaryLabelColor
        v.addSubview(text)
        return v
    }


    // MARK: - Voice list (Apple and Piper together)

    private var gewaehlteSprache: String {
        guard let w = sprachWahl, w.indexOfSelectedItem >= 0,
              w.indexOfSelectedItem < sprachen.count else { return Zuhoersprache.aktuell }
        return sprachen[w.indexOfSelectedItem].1
    }

    /// We always show voices in the chosen language AND in English.
    /// Anyone working in two languages shouldn't have to keep switching.
    private var sichtbareSprachen: [String] {
        var p = [String(gewaehlteSprache.prefix(2))]
        if !p.contains("en") { p.append("en") }
        return p
    }

    private static func fahne(_ sprache: String) -> String {
        switch String(sprache.prefix(2)) {
        case "de": return "DE"
        case "en": return "EN"
        case "fr": return "FR"
        case "es": return "ES"
        case "it": return "IT"
        case "nl": return "NL"
        case "pl": return "PL"
        case "pt": return "PT"
        case "tr": return "TR"
        default:   return String(sprache.prefix(2)).uppercased()
        }
    }

    private func stimmenLaden() {
        // Note: no check for sprachWahl here. It lives on another page, and
        // gewaehlteSprache already falls back to the system language without it.
        guard stimmWahl != nil else { return }
        stimmWahl.removeAllItems()

        let zeigen = sichtbareSprachen

        // Piper first — whatever is downloaded sounds best
        for k in PiperStimme.geladeneKlaenge
        where zeigen.contains(String(k.sprache.prefix(2))) {
            stimmWahl.addItem(withTitle:
                "\(Self.fahne(k.sprache))  Piper · \(k.name) (\(PiperStimme.gueteName(k.guete)))")
            stimmWahl.lastItem?.representedObject = "piper:\(k.kennung)"
        }

        let apple = AVSpeechSynthesisVoice.speechVoices()
            .filter { v in zeigen.contains(String(v.language.prefix(2))) }
            .sorted { a, b in
                // chosen language first, then English; best ones first within each
                let sa = zeigen.firstIndex(of: String(a.language.prefix(2))) ?? 9
                let sb = zeigen.firstIndex(of: String(b.language.prefix(2))) ?? 9
                if sa != sb { return sa < sb }
                let ra = Self.rang(a), rb = Self.rang(b)
                return ra == rb ? a.name < b.name : ra > rb
            }
        for v in apple {
            stimmWahl.addItem(withTitle: "\(Self.fahne(v.language))  \(Self.beschriftung(v))")
            stimmWahl.lastItem?.representedObject = v.identifier
        }
        if stimmWahl.numberOfItems == 0 {
            stimmWahl.addItem(withTitle: T.t("keine Stimme gefunden", "no voice found"))
            stimmWahl.isEnabled = false
            return
        }
        stimmWahl.isEnabled = true

        // restore the selection
        if let k = PiperStimme.gewaehlt,
           let i = (0..<stimmWahl.numberOfItems).first(where: {
               stimmWahl.item(at: $0)?.representedObject as? String == "piper:\(k.kennung)" }) {
            stimmWahl.selectItem(at: i)
        } else if let g = UserDefaults.standard.string(forKey: "stimme"),
                  let i = (0..<stimmWahl.numberOfItems).first(where: {
                      stimmWahl.item(at: $0)?.representedObject as? String == g }) {
            stimmWahl.selectItem(at: i)
        }
        stimmStand = stimmWahl.selectedItem?.representedObject as? String
    }

    private static func rang(_ s: AVSpeechSynthesisVoice) -> Int {
        if s.voiceTraits.contains(.isPersonalVoice) { return 3 }
        switch s.quality {
        case .premium: return 2
        case .enhanced: return 1
        default: return 0
        }
    }

    private static func beschriftung(_ s: AVSpeechSynthesisVoice) -> String {
        if s.voiceTraits.contains(.isPersonalVoice) { return T.t("\(s.name) — deine eigene Stimme", "\(s.name) — your own voice") }
        switch s.quality {
        case .premium: return "\(s.name) — Apple Premium"
        case .enhanced: return T.t("\(s.name) — Apple erweitert", "\(s.name) — Apple enhanced")
        default: return T.t("\(s.name) — Apple einfach", "\(s.name) — Apple basic")
        }
    }

    private func eigeneStimmeAnfragen() {
        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { _ in
            Task { @MainActor in self.stimmenLaden() }
        }
    }

    @objc private func spracheGewechselt() { stimmenLaden(); katalogLaden() }

    @objc private func updatePruefenUmschalten() {
        Neuigkeit.eingeschaltet.toggle()
    }

    @objc private func oberflaecheGewechselt() {
        let wahl = ["auto", "de", "en"][max(0, oberflaecheWahl.indexOfSelectedItem)]
        UserDefaults.standard.set(wahl, forKey: "oberflaeche")
        // The window is built by hand — rebuild it for the new language.
        // beiAenderung also makes the menu bar redraw itself in the new one.
        sichern()
        beiAenderung?()
        fenster?.close()
        fenster = nil
        zeigen()
    }

    // MARK: - Piper controls

    private var katalogAuswahl: PiperKlang? {
        guard let w = klangWahl,
              let k = w.selectedItem?.representedObject as? String else { return nil }
        return PiperStimme.katalog.first { $0.kennung == k }
    }

    private func katalogLaden() {
        guard klangWahl != nil, klangKnopf != nil else { return }
        klangWahl.removeAllItems()
        let zeigen = sichtbareSprachen
        let liste = PiperStimme.katalog
            .filter { zeigen.contains(String($0.sprache.prefix(2))) }
            .sorted { a, b in
                let sa = zeigen.firstIndex(of: String(a.sprache.prefix(2))) ?? 9
                let sb = zeigen.firstIndex(of: String(b.sprache.prefix(2))) ?? 9
                return sa == sb ? a.name < b.name : sa < sb
            }
        for k in liste {
            let da = PiperStimme.geladen(k) ? T.t("  ✓ geladen", "  ✓ ready") : "  \(k.mb) MB"
            klangWahl.addItem(withTitle:
                "\(Self.fahne(k.sprache))  \(k.name) (\(PiperStimme.gueteName(k.guete)))\(da)")
            klangWahl.lastItem?.representedObject = k.kennung
        }
        if klangWahl.numberOfItems == 0 {
            klangWahl.addItem(withTitle: T.t("für diese Sprache gibt es keine", "none for this language"))
            klangWahl.isEnabled = false
            klangKnopf.isEnabled = false
            return
        }
        klangWahl.isEnabled = PiperStimme.motorBereit
        klangGewechselt()
    }

    @objc private func klangGewechselt() {
        guard klangWahl != nil, klangKnopf != nil else { return }
        guard let k = katalogAuswahl else { return }
        klangKnopf.title = PiperStimme.geladen(k) ? T.t("löschen", "delete") : T.t("laden", "download")
        klangKnopf.isEnabled = PiperStimme.motorBereit
    }

    private func motorStandZeigen() {
        guard motorText != nil, motorKnopf != nil else { return }
        if PiperStimme.motorBereit {
            motorText.stringValue = T.t("Motor bereit · belegt \(PiperStimme.belegtMB) MB", "Engine ready · using \(PiperStimme.belegtMB) MB")
            motorText.textColor = .secondaryLabelColor
            motorKnopf.title = T.t("entfernen", "remove")
        } else {
            motorText.stringValue = T.t("Motor nicht eingerichtet (einmalig rund 190 MB)", "Engine not installed (one time, about 190 MB)")
            motorText.textColor = .secondaryLabelColor
            motorKnopf.title = T.t("einrichten", "install")
        }
        motorKnopf.isEnabled = true
    }

    @objc private func motorKnopfGedrueckt() {
        if !PiperStimme.motorBereit && PiperStimme.systemPython() == nil {
            Selbsthilfe.werkzeugeAnbieten()
            return
        }
        // Say it before the 190 MB, not after. Piper has voices for a lot of
        // languages, but only the ones in the catalogue have been checked —
        // and installing an engine that then has nothing to say is a waste of
        // somebody's evening.
        if !PiperStimme.motorBereit, !PiperStimme.gibtEsFuer(gewaehlteSprache) {
            let a = NSAlert()
            a.messageText = T.t("Für diese Sprache gibt es hier noch keine Piper-Stimme",
                                "No Piper voice for this language yet")
            a.informativeText = T.t("""
            Piper kann Deutsch und Englisch. Für deine eingestellte Sprache ist \
            keine Stimme dabei — der Motor braucht trotzdem rund 190 MB.

            Apples eigene Stimmen funktionieren in deiner Sprache und kosten nichts.
            """, """
            Piper here covers German and English. There is no voice for the \
            language you have chosen — the engine still needs about 190 MB.

            Apple’s own voices work in your language and cost nothing.
            """)
            a.addButton(withTitle: T.t("Trotzdem einrichten", "Install anyway"))
            a.addButton(withTitle: T.t("Lieber nicht", "Never mind"))
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        if PiperStimme.motorBereit {
            let a = NSAlert()
            a.messageText = T.t("Piper ganz entfernen?", "Remove Piper completely?")
            a.informativeText = T.t("Motor und alle geladenen Stimmen werden gelöscht — \(PiperStimme.belegtMB) MB. Hark spricht danach wieder mit Apples Stimmen.", "The engine and every downloaded voice will be deleted — \(PiperStimme.belegtMB) MB. Hark will speak with Apple’s voices again.")
            a.addButton(withTitle: T.t("Entfernen", "Remove")); a.addButton(withTitle: T.t("Behalten", "Keep"))
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return }
            PiperStimme.alesEntfernen()
            motorStandZeigen(); katalogLaden(); stimmenLaden()
            return
        }

        motorKnopf.isEnabled = false
        motorKnopf.title = T.t("läuft…", "working…")
        balken.isHidden = false
        balken.isIndeterminate = true
        balken.startAnimation(nil)
        balkenText.stringValue = T.t("beginne…", "starting…")

        // This runs for minutes. If the user clicks elsewhere in the sidebar
        // meanwhile, these controls no longer exist — so ask each time instead
        // of assuming. Without that, one click during the install or the
        // download killed the app on the spot.
        PiperStimme.motorEinrichten(schritt: { [weak self] stand in
            self?.balkenText?.stringValue = stand
        }, fertig: { [weak self] ok, meldung in
            guard let self else { return }
            self.balken?.stopAnimation(nil)
            self.balken?.isIndeterminate = false
            self.balken?.isHidden = true
            self.balkenText?.stringValue = meldung
            self.balkenText?.textColor = ok ? .systemGreen : .systemRed
            self.motorStandZeigen()
            self.katalogLaden()
        })
    }

    @objc private func klangKnopfGedrueckt() {
        guard let k = katalogAuswahl else { return }

        if PiperStimme.geladen(k) {
            PiperStimme.loescheKlang(k)
            katalogLaden(); stimmenLaden(); motorStandZeigen()
            balkenText.stringValue = T.t("\(k.name) gelöscht", "\(k.name) deleted")
            balkenText.textColor = .tertiaryLabelColor
            return
        }

        klangKnopf.isEnabled = false
        balken.isHidden = false
        balken.doubleValue = 0
        balkenText.textColor = .tertiaryLabelColor
        balkenText.stringValue = T.t("\(k.name): beginne…", "\(k.name): starting…")

        PiperStimme.ladeKlang(k, fortschritt: { [weak self] anteil, text in
            self?.balken?.doubleValue = anteil
            self?.balkenText?.stringValue = text
        }, fertig: { [weak self] ok, meldung in
            guard let self else { return }
            self.balken?.isHidden = true
            self.balkenText?.stringValue = ok ? T.t("\(k.name) ist geladen", "\(k.name) is ready") : meldung
            self.balkenText?.textColor = ok ? .systemGreen : .systemRed
            if ok { PiperStimme.gewaehlt = k }
            self.katalogLaden(); self.stimmenLaden(); self.motorStandZeigen()
        })
    }

    // MARK: - Preview

    private func dateiStandZeigen() {
        guard dateiFeld != nil else { return }
        let d = UserDefaults.standard.string(forKey: "vorleseDatei") ?? ""
        let pfad = d.isEmpty ? Sprecher.standardDatei : (d as NSString).expandingTildeInPath
        dateiFeld.stringValue = (pfad as NSString)
            .abbreviatingWithTildeInPath
    }

    @objc private func dateiZeigen() {
        let d = UserDefaults.standard.string(forKey: "vorleseDatei") ?? ""
        let pfad = d.isEmpty ? Sprecher.standardDatei : (d as NSString).expandingTildeInPath
        Sprecher.ortVorbereiten()
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: pfad)])
    }

    @objc private func claudeAnleitung() {
        Selbsthilfe.claudeAnleitungKopieren()
    }

    @objc private func dateiWaehlen() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        p.message = T.t("Welche Datei soll Hark vorlesen?",
                        "Which file should Hark read aloud?")
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let u = p.url else { return }
        UserDefaults.standard.set(u.path, forKey: "vorleseDatei")
        dateiStandZeigen()
        beiAenderung?()
    }

    @objc private func musikUmschalten(_ absender: NSButton) {
        Musik.eingeschaltet = (absender.state == .on)
        if !Musik.eingeschaltet { Musik.aufloesen() }
    }

    @objc private func autostartUmschalten() {
        let gewuenscht = autostartHaken.state == .on
        if !Autostart.setzen(gewuenscht) {
            autostartHaken.state = Autostart.an ? .on : .off
            let a = NSAlert()
            a.messageText = T.t("Autostart ging nicht", "Could not change startup")
            a.informativeText = T.t(
                "Das klappt erst, wenn Hark in „Programme“ liegt und einmal geöffnet wurde.",
                "This only works once Hark lives in Applications and has been opened once.")
            a.runModal()
        }
    }

    private func lautStandZeigen() {
        guard lautWert != nil, lautRegler != nil else { return }
        let w = Int(lautRegler.doubleValue.rounded())
        lautWert.stringValue = w == 0 ? T.t("nicht anfassen", "leave alone") : "\(w) %"
    }

    @objc private func lautGeaendert() {
        Lautstaerke.ziel = Int(lautRegler.doubleValue.rounded())
        lautStandZeigen()
    }

    @objc private func stimmeNachSpracheUmschalten() {
        Sprecher.stimmeNachSprache.toggle()
    }

    @objc private func tempoGeaendert() {
        UserDefaults.standard.set(tempoRegler.doubleValue, forKey: "sprechtempo")
    }

    @objc private func probeHoeren() {
        let text: String
        switch String(gewaehlteSprache.prefix(2)) {
        case "de": text = "So klingt Hark. Sag einfach dein Weckwort, dann höre ich zu."
        case "fr": text = "Voici la voix de Hark. Dites votre mot-clé, j’écoute."
        case "es": text = "Así suena Hark. Di tu palabra clave y te escucho."
        case "it": text = "Così suona Hark. Di’ la tua parola chiave e ti ascolto."
        default:   text = "This is how Hark sounds. Just say your wake word and I’m listening."
        }

        let wahl = stimmWahl.selectedItem?.representedObject as? String ?? ""
        if wahl.hasPrefix("piper:") {
            let kennung = String(wahl.dropFirst(6))
            if let k = PiperStimme.katalog.first(where: { $0.kennung == kennung }) {
                // Listening to a voice must not quietly change the setting.
                let vorher = PiperStimme.gewaehlt?.kennung
                PiperStimme.gewaehlt = k
                piperProbe.sprich(text) { _ in
                    PiperStimme.gewaehlt = PiperStimme.katalog.first { $0.kennung == vorher }
                }
                return
            }
        }
        let a = AVSpeechUtterance(string: text)
        a.voice = AVSpeechSynthesisVoice(identifier: wahl)
        a.rate = Float(tempoRegler.doubleValue)
        sprecher.stopSpeaking(at: .immediate)
        sprecher.speak(a)
    }

    @objc private func stimmenLadenOeffnen() {
        let a = NSAlert()
        a.messageText = T.t("Apples eigene Stimmen laden", "Download Apple’s better voices")
        a.informativeText = T.t("""
        Apple hat bessere Stimmen als die vorinstallierten — wo der Knopf sitzt, \
        hängt von deiner macOS-Version ab. Beide Wege:

        1.  Ich öffne dir gleich „Bedienungshilfen → Vorlesen“.
        2.  Suche die Zeile „Systemstimme“.
        3.  Neuere Systeme: rechts daneben auf das ⓘ klicken.
        4.  Ältere Systeme: auf den Namen der Stimme klicken, ganz unten \
        steht „Stimmen verwalten…“.
        5.  Deutsch aufklappen, alles mit „Premium“ laden. \
        Finger weg von „Eloquence“ — das ist Apples alte Roboter-Familie.
        6.  Danach hier das Fenster einmal zu und wieder auf.
        """, """
        Apple ships better voices than the preinstalled ones — where the button \
        lives depends on your macOS version. Both routes:

        1.  I will open “Accessibility → Spoken Content” for you.
        2.  Find the row “System voice”.
        3.  Newer systems: click the ⓘ to its right.
        4.  Older systems: click the voice name, then “Manage Voices…” at the \
        very bottom of the list.
        5.  Expand your language and download anything marked “Premium”. \
        Stay away from “Eloquence” — that is Apple’s old robot family.
        6.  Afterwards close this window once and reopen it.
        """)
        a.addButton(withTitle: T.t("Einstellungen öffnen", "Open Settings")); a.addButton(withTitle: T.t("Später", "Later"))
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent")!)
        }
    }

    @objc private func eigeneStimmeErklaeren() {
        let a = NSAlert()
        a.messageText = T.t("Hark mit deiner eigenen Stimme", "Hark in your own voice")
        a.informativeText = T.t("""
        Dein Mac kann eine Stimme aus deiner eigenen aufnehmen. Danach klingt \
        Hark wie du. Das passiert vollständig auf diesem Gerät.

        1.  Bedienungshilfen → „Persönliche Stimme“.
        2.  „Persönliche Stimme erstellen“, Namen vergeben.
        3.  Etwa 150 Sätze vorlesen, gut eine halbe Stunde, ruhiger Raum.
        4.  Der Mac rechnet über Nacht, angesteckt und zugeklappt.
        5.  Am nächsten Tag steht sie hier ganz oben in der Liste.
        """, """
        Your Mac can build a voice from your own. Hark then sounds like you. \
        All of it happens on this device.

        1.  Accessibility → “Personal Voice”.
        2.  “Create a Personal Voice”, give it a name.
        3.  Read about 150 sentences aloud, roughly half an hour, quiet room.
        4.  The Mac trains overnight, plugged in and closed.
        5.  Next day it appears at the top of the list here.
        """)
        a.addButton(withTitle: T.t("Einstellungen öffnen", "Open Settings")); a.addButton(withTitle: T.t("Später", "Later"))
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.universalaccess?PersonalVoice")!)
        }
    }

    // MARK: - Saving

    /// What the voice popup showed when the page was built. That is how we
    /// tell a real choice from "the list simply had no room for the saved one".
    private var stimmStand: String?

    /// Only the page that is currently built has its controls in memory.
    /// Everything else keeps whatever it had — so switching pages can never
    /// wipe a setting the user cannot even see right now.
    private func sichern() {
        // A text field only hands its text over when it loses focus. Saving
        // with the cursor still in it would store the old value. But only take
        // the focus away if a field really has it — otherwise the sidebar
        // loses its keyboard focus on every single click.
        if let f = fenster, f.firstResponder is NSTextView {
            f.makeFirstResponder(nil)
        }
        let d = UserDefaults.standard

        if let f = weckwortFeld {
            let wort = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            d.set(wort.isEmpty ? "hey hark" : wort.lowercased(), forKey: "weckwort")
        }
        if let w = sprachWahl, w.indexOfSelectedItem >= 0,
           w.indexOfSelectedItem < sprachen.count {
            d.set(sprachen[w.indexOfSelectedItem].1, forKey: "sprache")
        }
        // Only if it really changed. The list shows voices for the chosen
        // listening language only, so a saved voice in another language is not
        // in it — and the popup then sits on the first entry. Writing that back
        // would throw the chosen voice away just for opening the page.
        if let w = stimmWahl, let wahl = w.selectedItem?.representedObject as? String,
           wahl != stimmStand {
            if wahl.hasPrefix("piper:") {
                let kennung = String(wahl.dropFirst(6))
                PiperStimme.gewaehlt = PiperStimme.katalog.first { $0.kennung == kennung }
            } else {
                PiperStimme.gewaehlt = nil
                if !wahl.isEmpty { d.set(wahl, forKey: "stimme") }
            }
        }
        if let f = pausenFeld {
            let pause = Double(f.stringValue.replacingOccurrences(of: ",", with: ".")) ?? 1.8
            d.set(min(max(pause, 0.5), 6.0), forKey: "stillePause")
        }
        if let h = eingabeHaken { d.set(h.state == .on, forKey: "eingabeDruecken") }
        if let h = mittippenHaken { d.set(h.state == .on, forKey: "weckwortMittippen") }
        if let f = woerterFeld { d.set(f.string, forKey: "eigeneWoerter") }
        if let h = serverHaken { d.set(h.state == .on, forKey: "serverErkennung") }
        if let r = tempoRegler { d.set(r.doubleValue, forKey: "sprechtempo") }
        if let r = lautRegler { Lautstaerke.ziel = Int(r.doubleValue.rounded()) }
        beiAenderung?()
    }

    @objc private func sichernUndSchliessen() { fenster?.performClose(nil) }

    // MARK: - Sidebar

    func numberOfRows(in tableView: NSTableView) -> Int { seiten.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let z = NSTextField(labelWithString: seiten[row].0)
        z.font = .systemFont(ofSize: 13)
        let huelle = NSView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        z.frame = NSRect(x: 10, y: 6, width: 146, height: 18)
        huelle.addSubview(z)
        return huelle
    }

    func tableViewSelectionDidChange(_ n: Notification) {
        guard let leiste = seitenleiste, leiste.selectedRow >= 0 else { return }
        // Save whatever the page we are leaving had, so nothing is lost
        // just because the user clicked elsewhere in the sidebar.
        sichern()
        seiteZeigen(leiste.selectedRow)
    }
}
