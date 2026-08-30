// Hoerer.swift — listens for the wake word. All on device, nothing online.

import AVFoundation
import Foundation
import Speech

/// Small wrapper so Swift 6 allows handing this to the audio thread.
private final class Truhe<T>: @unchecked Sendable {
    let inhalt: T
    init(_ inhalt: T) { self.inhalt = inhalt }
}

/// Last sign of life from the audio thread. Read by the watchdog.
private final class Puls: @unchecked Sendable {
    private var wert = Date()
    private let riegel = NSLock()
    func schlag() { riegel.lock(); wert = Date(); riegel.unlock() }
    var letzter: Date { riegel.lock(); defer { riegel.unlock() }; return wert }
}

@MainActor
final class Hoerer {

    enum Lage {
        case aus
        case keineErlaubnis(String)
        case wartetAufWeckwort
        case nimmtAuf
    }

    // called when the wake word lands
    var beiWeckwort: (() -> Void)?
    // called when the sentence after it is finished
    var beiDiktat: ((String) -> Void)?
    // called when the state changes
    var beiLageWechsel: ((Lage) -> Void)?

    /// While Hark is talking it turns a deaf ear — otherwise it wakes itself.
    ///
    /// Looking away is not enough on its own: the recogniser keeps collecting
    /// audio the whole time, so Hark's own words sit in the transcript waiting.
    /// The moment it listens again they all arrive at once — and a sentence
    /// containing the word "Jarvis" is enough to set the whole thing off. So
    /// when the deafness lifts we throw the round away and start clean.
    var taub = false {
        didSet {
            guard oldValue != taub else { return }
            if taub {
                stilleUhr?.invalidate()
            } else {
                // Brief grace period: the tail of the loudspeaker is still
                // in the microphone buffer for a moment. Until the new round
                // is running we ignore everything — otherwise Hark's own words
                // end up in the sentence, which is exactly what used to happen.
                taubRunde = runde
                Timer.harkUhr(0.6) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, !self.taub else { return }
                        switch self.lage {
                        case .aus, .keineErlaubnis:
                            return
                        case .nimmtAuf:
                            // We were mid-sentence when Hark began to speak.
                            // Keep what we had — the new round gets a fresh
                            // recogniser, so Hark's own words are not in it —
                            // and wind the pause clock back up. Without this
                            // the sentence was lost, and everything said
                            // afterwards was thrown away as well.
                            self.diktatBasis = self.diktat
                            self.inFolgeRunde = true
                            // With extra time on the clock. The round starting
                            // here needs a moment before it delivers its first
                            // words, and the normal pause would run out in
                            // between — Hark would then finish the sentence
                            // while you were still in the middle of it.
                            self.stilleUhrStellen(zusatz: 2.5)
                        default:
                            break
                        }
                        try? self.laufRundeStarten()
                    }
                }
            }
        }
    }

    /// When the current round really began listening. A round that ends
    /// again within a second did not run — it failed.
    private var rundeSeit = Date.distantPast

    /// The round that was running when Hark stopped talking. Everything up
    /// to and including it is ignored: the engine goes on collecting while
    /// Hark talks, so its own words sit in that round's buffer and arrive all
    /// at once the moment we listen again. A clock cannot tell the two apart,
    /// a round number can.
    private var taubRunde = -1

    private(set) var lage: Lage = .aus {
        didSet { beiLageWechsel?(lage) }
    }

    var weckwort: String {
        let gespeichert = UserDefaults.standard.string(forKey: "weckwort") ?? ""
        return gespeichert.isEmpty ? "hey hark" : gespeichert.lowercased()
        // "hey hark" works in both languages — so no difference here.
    }

    private let motor = AVAudioEngine()
    private var erkenner: SFSpeechRecognizer?
    private var anfrage: SFSpeechAudioBufferRecognitionRequest?
    private var aufgabe: SFSpeechRecognitionTask?
    private var neustartUhr: Timer?
    private var stilleUhr: Timer?
    private var zuletztErkannt = Date.distantPast
    private let puls = Puls()
    private var wachhund: Timer?
    private var fehlversuche = 0
    /// Guards against two starts overlapping. The permission callback is
    /// asynchronous, so a quick stop-start-stop-start could otherwise get two
    /// taps onto the same audio bus — and AVAudioEngine throws for that, which
    /// on macOS means the app is gone, not an error you can catch.
    private var startetGerade = false
    /// Counts the rounds. Every restart bumps it, and callbacks from an older
    /// round are ignored. Without this, cancelling a task on purpose looks
    /// exactly like the engine failing — which is precisely the mistake that
    /// made Hark declare itself broken after a few normal dictations.
    private var runde = 0
    private var diktat = ""
    /// What earlier rounds of the same sentence already produced.
    ///
    /// Apple ends a recognition session after roughly a minute, whether you
    /// are finished or not. Without carrying the text across that boundary,
    /// anything you say beyond it is simply lost — and you only notice
    /// afterwards, mid-thought, which is the worst possible moment.
    private var diktatBasis = ""
    private var inFolgeRunde = false

    /// Type the wake word along with the sentence?
    ///
    /// Off by default, because "hey jarvis" in the middle of your text is
    /// usually noise. On, it becomes a signal: whoever reads the message can
    /// tell it was spoken rather than typed, without being told.
    var weckwortMittippen: Bool {
        UserDefaults.standard.bool(forKey: "weckwortMittippen")
    }

    /// Words the user told us about: names, projects, jargon.
    static var eigeneWoerter: [String] {
        (UserDefaults.standard.string(forKey: "eigeneWoerter") ?? "")
            .split(whereSeparator: { ",;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// How much quiet before the sentence counts as finished.
    private var stillePause: Double {
        let wert = UserDefaults.standard.double(forKey: "stillePause")
        return wert > 0.4 ? wert : 1.8
    }

    // MARK: - On and off

    func starten() {
        guard !startetGerade else { return }
        switch lage {
        case .aus:
            break
        case .keineErlaubnis:
            // "Listening keeps failing" used to be a dead end: the menu
            // offered "resume" and this method quietly did nothing at all.
            // Let go of the leftovers and start again properly.
            stoppen()
        default:
            return                  // already listening
        }
        startetGerade = true
        erlaubnisHolen { [weak self] fehler in
            guard let self else { return }
            self.startetGerade = false
            if let fehler {
                self.lage = .keineErlaubnis(fehler)
            } else {
                self.lauschenBeginnen()
            }
        }
    }

    /// Something interrupted the recognition. Quietly pick it back up.
    /// Backs off a little each time so a broken microphone does not turn
    /// into a busy loop.
    private func wiederAufsetzen(echterFehler: Bool = true) {
        switch lage {
        case .aus, .keineErlaubnis: return
        default: break
        }

        // Whatever the reason: if we are in the middle of a sentence, what we
        // already have has to survive into the next round. Carrying it only on
        // the tidy path was the bug where Hark stopped writing halfway through
        // while you were still talking — everything after went into a round
        // that was waiting for the wake word again.
        if case .nimmtAuf = lage {
            diktatBasis = diktat
            inFolgeRunde = true
        }

        // A round that simply ended is not a failure — as long as it really
        // ran. If "finished" arrives right after starting, that is a failure
        // wearing a different hat, and picking straight back up would spin.
        if !echterFehler, Date().timeIntervalSince(rundeSeit) > 1 {
            // It ran, so the chain is intact. Without this the count crept up
            // over hours in a quiet room until Hark declared itself broken for
            // no reason at all.
            fehlversuche = 0
            try? laufRundeStarten()
            return
        }

        fehlversuche += 1
        let warten = min(0.6 * Double(fehlversuche), 8.0)

        if fehlversuche > 6 {
            // Six failures in a row is not a hiccup. Say so instead of
            // pretending to listen.
            // Also let go of the microphone: otherwise the orange recording
            // dot stays on for a Hark that has stopped listening.
            let grund = T.t("Zuhören klemmt — im Menü pausieren und wieder starten",
                            "listening keeps failing — pause and resume in the menu")
            stoppen()
            lage = .keineErlaubnis(grund)
            return
        }

        Timer.harkUhr(warten) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                switch self.lage {
                case .aus, .keineErlaubnis: return
                default: try? self.laufRundeStarten()
                }
            }
        }
    }

    private func regung() {
        // A result came through, so the chain is intact.
        fehlversuche = 0
    }

    /// Watches the audio thread. If no buffer arrives for a while the engine
    /// has died without telling anyone — that happens after waking from sleep
    /// or when the microphone is switched.
    private func wachhundStellen() {
        wachhund?.invalidate()
        wachhund = Timer.harkUhr(10, wiederholt: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                switch self.lage {
                case .aus, .keineErlaubnis: return
                default: break
                }
                if Date().timeIntervalSince(self.puls.letzter) > 12 {
                    self.wiederAufsetzen()
                }
            }
        }
    }

    func stoppen() {
        runde += 1          // ignore anything the running task says from now on
        startetGerade = false
        wachhund?.invalidate()
        wachhund = nil
        fehlversuche = 0
        neustartUhr?.invalidate()
        neustartUhr = nil
        stilleUhr?.invalidate()
        stilleUhr = nil
        aufgabe?.cancel()
        aufgabe = nil
        anfrage?.endAudio()
        anfrage = nil
        if motor.isRunning {
            motor.stop()
            motor.inputNode.removeTap(onBus: 0)
        }
        lage = .aus
    }

    // MARK: - Permissions

    private func erlaubnisHolen(_ fertig: @escaping (String?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    fertig(T.t("Spracherkennung nicht erlaubt", "speech recognition not allowed"))
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { erlaubt in
                    Task { @MainActor in
                        fertig(erlaubt ? nil : T.t("Mikrofon nicht erlaubt", "microphone not allowed"))
                    }
                }
            }
        }
    }

    // MARK: - Listening

    private func lauschenBeginnen() {
        let sprache = Zuhoersprache.aktuell
        guard let erkenner = SFSpeechRecognizer(locale: Locale(identifier: sprache)),
              erkenner.isAvailable else {
            lage = .keineErlaubnis("SPRACHE_FEHLT")
            return
        }
        self.erkenner = erkenner

        // The watchdog first: if the start fails, it is the one thing that
        // tries again. Set up afterwards it was skipped exactly when it was
        // needed, and a microphone that was busy for one second parked Hark
        // for good.
        wachhundStellen()
        lage = .wartetAufWeckwort
        do {
            try laufRundeStarten()
        } catch {
            // Not a dead end: count it and try again shortly. After six goes
            // it says so honestly instead of pretending to listen.
            wiederAufsetzen()
        }
    }

    /// Apple ends a recognition on its own after about a minute.
    /// So we run in rounds and quietly start over from the top.
    private func laufRundeStarten() throws {
        runde += 1          // everything the old task still says is now stale
        aufgabe?.cancel()
        aufgabe = nil
        if motor.isRunning {
            motor.stop()
            motor.inputNode.removeTap(onBus: 0)
        }

        let anfrage = SFSpeechAudioBufferRecognitionRequest()
        anfrage.shouldReportPartialResults = true

        // Off by default and clearly labelled in Settings. On device the model
        // is smaller and therefore less accurate; Apple's server model is
        // markedly better. That is a trade the user makes, not us.
        anfrage.requiresOnDeviceRecognition = !UserDefaults.standard.bool(forKey: "serverErkennung")

        // Tell the recogniser what kind of speech to expect. Without this it
        // assumes short commands and guesses badly at whole sentences.
        anfrage.taskHint = .dictation

        // Punctuation from the spoken pauses. Apple does this well and it
        // turns a wall of words into readable text.
        if #available(macOS 13.0, *) {
            anfrage.addsPunctuation = true
        }
        // Apple's model barely knows rare names like "Hark". Here we tell
        // it explicitly what to expect — that lifts the hit rate for this
        // one wake word considerably.
        var erwartet = [weckwort]
        erwartet += weckwort.split(separator: " ").map(String.init)
        // Names the model has never heard — project names, people, jargon.
        // This is the single most effective knob there is: a word listed here
        // goes from "never recognised" to "almost always right".
        erwartet += Self.eigeneWoerter
        anfrage.contextualStrings = Array(Set(erwartet)).filter { !$0.isEmpty }
        self.anfrage = anfrage

        let eingang = motor.inputNode
        // Belt and braces: removing a tap that is not there is harmless,
        // installing a second one onto the same bus is fatal.
        eingang.removeTap(onBus: 0)
        let format = eingang.outputFormat(forBus: 0)
        // While the input device is changing — headphones connecting, a
        // microphone unplugged, waking from sleep — this comes back empty.
        // Handing that to installTap does not throw, it kills the app on the
        // spot. Better to skip this round; the watchdog tries again shortly.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "studio.bazo.hark", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "kein brauchbarer Toneingang"])
        }
        let truhe = Truhe(anfrage)
        let puls = self.puls
        eingang.installTap(onBus: 0, bufferSize: 2048, format: format) { puffer, _ in
            truhe.inhalt.append(puffer)
            puls.schlag()
        }

        motor.prepare()
        try motor.start()
        rundeSeit = Date()

        let meineRunde = runde

        aufgabe = erkenner?.recognitionTask(with: anfrage) { [weak self] ergebnis, fehler in
            if let text = ergebnis?.bestTranscription.formattedString {
                Task { @MainActor in
                    guard let self, meineRunde == self.runde else { return }
                    self.regung()
                    self.pruefen(text)
                }
            }
            // Apple's engine stops for two very different reasons: it finished
            // its round, or it broke. Only the second one is a failure. And a
            // callback from a round we already replaced is neither — it is
            // just the old task saying goodbye.
            if fehler != nil || ergebnis?.isFinal == true {
                let echterFehler = fehler != nil
                Task { @MainActor in
                    guard let self, meineRunde == self.runde else { return }
                    self.wiederAufsetzen(echterFehler: echterFehler)
                }
            }
        }

        neustartUhr?.invalidate()
        neustartUhr = Timer.harkUhr(50) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .wartetAufWeckwort = self.lage else { return }
                try? self.laufRundeStarten()
            }
        }
    }

    // MARK: - Spotting the wake word

    private func pruefen(_ roh: String) {
        guard !taub, runde > taubRunde else { return }
        // For searching we need lowercased text without punctuation.
        // For typing we need the original — otherwise "Test" becomes
        // "test", and in German that looks wrong.
        let rohWoerter = roh.split(separator: " ").map(String.init)
        let suchWoerter = rohWoerter.map {
            $0.lowercased()
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: "!", with: "")
                .replacingOccurrences(of: "?", with: "")
        }

        let spanne = Self.weckwortSpanne(weckwort, in: suchWoerter)
        let ab = spanne?.ende

        // Mid-dictation we accept a round without the wake word: the engine
        // restarted on its own, and this is simply the rest of the sentence.
        let rest: String
        if let spanne {
            // Either from behind the wake word, or from the wake word itself.
            let von = weckwortMittippen ? spanne.start : spanne.ende
            rest = rohWoerter[von...].joined(separator: " ")
        } else if case .nimmtAuf = lage, inFolgeRunde {
            rest = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return
        }

        let ganz = diktatBasis.isEmpty
            ? rest
            : (diktatBasis + " " + rest).trimmingCharacters(in: .whitespacesAndNewlines)

        switch lage {

        case .wartetAufWeckwort:
            guard ab != nil else { return }
            guard Date().timeIntervalSince(zuletztErkannt) > 2 else { return }
            zuletztErkannt = Date()
            diktatBasis = ""
            inFolgeRunde = false
            diktat = rest
            lage = .nimmtAuf
            beiWeckwort?()
            // Extra time right at the start. Between the wake word and your
            // first real word a lot happens: Apple needs a moment to report the
            // wake word at all, the music has to be asked to stop, and most
            // people wait for that silence before they begin. The normal pause
            // ran out in the middle of it and ended the sentence before it had
            // started — which is why only the wake word arrived.
            stilleUhrStellen(zusatz: 3.0)

        case .nimmtAuf:
            if ganz != diktat {
                // Hark's own voice coming back through the microphone: you
                // played the answer back from somewhere. Throw the round away
                // rather than type Hark's words into your chat as if they were
                // yours. Going back to waiting also lets the music run again.
                if Sprecher.stammtVonUns(ganz) {
                    diktat = ""
                    diktatBasis = ""
                    inFolgeRunde = false
                    zuletztErkannt = Date()
                    stilleUhr?.invalidate()
                    lage = .wartetAufWeckwort
                    try? laufRundeStarten()
                    return
                }
                diktat = ganz
                stilleUhrStellen()   // still talking — wind the clock back
            }

        default:
            break
        }
    }

    private func stilleUhrStellen(zusatz: TimeInterval = 0) {
        stilleUhr?.invalidate()
        stilleUhr = Timer.harkUhr(stillePause + zusatz) { [weak self] _ in
            Task { @MainActor in self?.diktatAbschliessen() }
        }
    }

    private func diktatAbschliessen() {
        guard case .nimmtAuf = lage else { return }
        let satz = diktat.trimmingCharacters(in: .whitespacesAndNewlines)
        diktat = ""
        diktatBasis = ""
        inFolgeRunde = false
        zuletztErkannt = Date()
        lage = .wartetAufWeckwort
        try? laufRundeStarten()      // fresh round, so the old text is gone
        // Report even an empty sentence, so the caller can tell "finished
        // with nothing" from "still recording".
        beiDiktat?(satz)
    }
}

// MARK: - Forgiving word comparison

extension Hoerer {

    /// How many letters do you have to change to get from a to b?
    static func abstand(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var vorige = Array(0...b.count)
        var jetzige = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            jetzige[0] = i
            for j in 1...b.count {
                let preis = a[i - 1] == b[j - 1] ? 0 : 1
                jetzige[j] = min(jetzige[j - 1] + 1,
                                 vorige[j] + 1,
                                 vorige[j - 1] + preis)
            }
            vorige = jetzige
        }
        return vorige[b.count]
    }

    /// Where the wake word starts and ends. The caller decides whether to cut
    /// it off or keep it.
    static func weckwortSpanne(_ weckwort: String,
                               in woerter: [String]) -> (start: Int, ende: Int)? {
        let teile = weckwort.split(separator: " ").map(String.init)
        guard !teile.isEmpty, !woerter.isEmpty else { return nil }

        // Room for error per word, instead of one budget spread over the
        // whole phrase. Words under five letters get none: with a single free
        // letter "hark" also matches mark, park, dark, bark, lark and hard —
        // and a wake word that fires by mistake types a whole sentence into
        // whatever happens to be in front, Return included. So a short wake
        // word has to be heard exactly. From five letters up there is room for
        // a slip, and more the longer the word: "jarvis" may be off by two,
        // the little "hey" in front of it by none.
        func spielraum(_ wort: String) -> Int {
            wort.count < 5 ? 0 : max(1, wort.count / 3)
        }

        if woerter.count >= teile.count {
            for start in 0...(woerter.count - teile.count) {
                var passt = true
                for (i, teil) in teile.enumerated() {
                    if abstand(woerter[start + i], teil) > spielraum(teil) {
                        passt = false
                        break
                    }
                }
                if passt { return (start, start + teile.count) }
            }
        }

        // Sometimes the transcription glues the words together ("heyhark") or
        // pulls one apart. Then a window of the right length can never match,
        // however close the letters are. So we also try one word more and one
        // word less, on the letters without the spaces.
        let ziel = weckwort.replacingOccurrences(of: " ", with: "")
        let luft = ziel.count < 6 ? 0 : ziel.count / 4
        for laenge in [teile.count - 1, teile.count + 1]
        where laenge >= 1 && laenge <= woerter.count {
            for start in 0...(woerter.count - laenge) {
                if abstand(woerter[start..<(start + laenge)].joined(), ziel) <= luft {
                    return (start, start + laenge)
                }
            }
        }
        return nil
    }
}
