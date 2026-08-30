// PiperStimme.swift — neural voices, offline, via Piper.
//
// Two things are downloaded separately:
//   the engine (Python + the Piper package, once, around 190 MB)
//   the voices (20 to 110 MB each, as many as you like)

import AVFoundation
import Foundation

struct PiperKlang: Sendable, Equatable {
    let kennung: String      // de_DE-thorsten-medium
    let name: String         // Thorsten
    let sprache: String      // de-DE
    let guete: String        // mittel
    let pfad: String         // de/de_DE/thorsten/medium
    let mb: Int
}

@MainActor
final class PiperStimme {

    // MARK: - Catalogue

    /// The catalogue keeps the quality as a plain word, and that word used to
    /// go straight into the list — so an English user read "Amy (mittel)".
    nonisolated static func gueteName(_ g: String) -> String {
        switch g {
        case "hoch":         return T.t("hoch", "high")
        case "mittel":       return T.t("mittel", "medium")
        case "niedrig":      return T.t("niedrig", "low")
        case "sehr niedrig": return T.t("sehr niedrig", "very low")
        default:             return g
        }
    }

    /// Is there a Piper voice at all for this listening language? Without this
    /// someone could install a 190 MB engine first and only then be told there
    /// is nothing to say it with.
    nonisolated static func gibtEsFuer(_ sprache: String) -> Bool {
        let kurz = String(sprache.prefix(2))
        return katalog.contains { $0.sprache.hasPrefix(kurz) }
    }

    nonisolated static let katalog: [PiperKlang] = [
        .init(kennung: "de_DE-thorsten-medium", name: "Thorsten", sprache: "de-DE",
              guete: "mittel", pfad: "de/de_DE/thorsten/medium", mb: 63),
        .init(kennung: "de_DE-thorsten-high", name: "Thorsten", sprache: "de-DE",
              guete: "hoch", pfad: "de/de_DE/thorsten/high", mb: 114),
        .init(kennung: "de_DE-thorsten-low", name: "Thorsten", sprache: "de-DE",
              guete: "niedrig", pfad: "de/de_DE/thorsten/low", mb: 63),
        .init(kennung: "de_DE-eva_k-x_low", name: "Eva K.", sprache: "de-DE",
              guete: "sehr niedrig", pfad: "de/de_DE/eva_k/x_low", mb: 21),
        .init(kennung: "de_DE-kerstin-low", name: "Kerstin", sprache: "de-DE",
              guete: "niedrig", pfad: "de/de_DE/kerstin/low", mb: 63),
        .init(kennung: "de_DE-ramona-low", name: "Ramona", sprache: "de-DE",
              guete: "niedrig", pfad: "de/de_DE/ramona/low", mb: 63),
        .init(kennung: "de_DE-karlsson-low", name: "Karlsson", sprache: "de-DE",
              guete: "niedrig", pfad: "de/de_DE/karlsson/low", mb: 63),
        .init(kennung: "de_DE-pavoque-low", name: "Pavoque", sprache: "de-DE",
              guete: "niedrig", pfad: "de/de_DE/pavoque/low", mb: 63),
        .init(kennung: "en_US-amy-medium", name: "Amy", sprache: "en-US",
              guete: "mittel", pfad: "en/en_US/amy/medium", mb: 63),
        .init(kennung: "en_US-ryan-high", name: "Ryan", sprache: "en-US",
              guete: "hoch", pfad: "en/en_US/ryan/high", mb: 114),
        .init(kennung: "en_GB-alan-medium", name: "Alan", sprache: "en-GB",
              guete: "mittel", pfad: "en/en_GB/alan/medium", mb: 63),
    ]

    // MARK: - Places

    nonisolated static let ordner = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/Application Support/Hark/piper")

    nonisolated static var python: String {
        (ordner as NSString).appendingPathComponent("venv/bin/python")
    }

    nonisolated static func modellPfad(_ k: PiperKlang) -> String {
        (ordner as NSString).appendingPathComponent("\(k.kennung).onnx")
    }

    nonisolated static func geladen(_ k: PiperKlang) -> Bool {
        FileManager.default.fileExists(atPath: modellPfad(k))
            && FileManager.default.fileExists(atPath: modellPfad(k) + ".json")
    }

    nonisolated static var motorBereit: Bool {
        FileManager.default.isExecutableFile(atPath: python)
    }

    nonisolated static var geladeneKlaenge: [PiperKlang] { katalog.filter { geladen($0) } }

    /// Which Piper voice is selected? nil means: use an Apple voice.
    nonisolated static var gewaehlt: PiperKlang? {
        get {
            guard motorBereit,
                  let k = UserDefaults.standard.string(forKey: "piperKlang"),
                  let treffer = katalog.first(where: { $0.kennung == k }),
                  geladen(treffer) else { return nil }
            return treffer
        }
        set { UserDefaults.standard.set(newValue?.kennung, forKey: "piperKlang") }
    }

    nonisolated static var belegtMB: Int {
        guard let auf = try? FileManager.default.subpathsOfDirectory(atPath: ordner) else { return 0 }
        var summe: Int64 = 0
        for p in auf {
            let voll = (ordner as NSString).appendingPathComponent(p)
            if let a = try? FileManager.default.attributesOfItem(atPath: voll),
               let g = a[.size] as? Int64 { summe += g }
        }
        return Int(summe / 1_048_576)
    }

    // MARK: - Speaking

    private var spieler: AVAudioPlayer?
    private var warteschlange: [String] = []      // finished pieces, in order
    private var kette: Timer?
    private var redetNoch = false
    private var allesGebaut = true
    private var gemeldet = true
    private var letzteRegung = Date.distantPast
    private var stueckBis = Date.distantPast
    private var lauf = 0
    private var abbruchFlagge: Abbruch?

    /// True for the whole utterance, not just while sound is actually coming
    /// out. The tenth of a second between two pieces would otherwise look like
    /// "finished", and the ear would open in the middle of a sentence.
    var redetGerade: Bool { redetNoch }

    func abbrechen() {
        lauf += 1
        abbruchFlagge?.setzen()
        abbruchFlagge = nil
        kette?.invalidate(); kette = nil
        spieler?.stop(); spieler = nil
        for p in warteschlange { try? FileManager.default.removeItem(atPath: p) }
        warteschlange = []
        redetNoch = false
        allesGebaut = true
        gemeldet = true
    }

    /// Piper needs about as long to build the sound as the sound then lasts.
    /// Building the whole answer first and only then starting to speak means
    /// sitting in silence for seconds — that was the wait you could hear. So
    /// we cut the text into pieces, start on the first one the moment it is
    /// ready, and go on building the rest while it plays.
    func sprich(_ text: String, fertig: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard let klang = Self.gewaehlt else { fertig(false); return }
        abbrechen()

        lauf += 1
        let meinLauf = lauf
        let flagge = Abbruch()
        abbruchFlagge = flagge
        redetNoch = true
        allesGebaut = false
        gemeldet = false
        letzteRegung = Date()
        ketteStellen()

        let teile = Self.haeppchen(text)
        let python = Self.python
        let modell = Self.modellPfad(klang)

        DispatchQueue.global(qos: .userInitiated).async {
            for stueck in teile {
                if flagge.gesetzt { break }
                let ziel = (NSTemporaryDirectory() as NSString)
                    .appendingPathComponent("hark-\(UUID().uuidString).wav")
                let ok = Self.erzeuge(text: stueck, python: python, modell: modell, ziel: ziel)
                Task { @MainActor [weak self] in
                    // redetNoch too: if the reading has already been declared
                    // over, a piece arriving late must not start playing — the
                    // ear is open again by then, and Hark would transcribe
                    // itself straight back into the chat.
                    guard let self, meinLauf == self.lauf, self.redetNoch else {
                        try? FileManager.default.removeItem(atPath: ziel)
                        return
                    }
                    guard ok else { return }
                    self.warteschlange.append(ziel)
                    self.letzteRegung = Date()
                    self.weiter()
                    if !self.gemeldet, self.spieler != nil {
                        self.gemeldet = true
                        fertig(true)
                    }
                }
            }
            Task { @MainActor [weak self] in
                guard let self, meinLauf == self.lauf else { return }
                self.allesGebaut = true
                if !self.gemeldet {
                    // Not a single piece came out. Better to let Apple say it
                    // than to leave the answer unspoken.
                    self.gemeldet = true
                    self.redetNoch = false
                    self.kette?.invalidate(); self.kette = nil
                    fertig(false)
                }
            }
        }
    }

    private func ketteStellen() {
        kette?.invalidate()
        kette = Timer.harkUhr(0.1, wiederholt: true) { [weak self] _ in
            Task { @MainActor in self?.weiter() }
        }
    }

    /// Starts the next piece as soon as the one before it has finished.
    private func weiter() {
        // A player that still claims to be playing well past the end of its own
        // piece has got stuck. Without this ceiling the reading would count as
        // running for ever — and the ear would stay deaf with it.
        if let s = spieler, s.isPlaying, Date() < stueckBis { return }
        spieler?.stop()
        spieler = nil

        while !warteschlange.isEmpty {
            let pfad = warteschlange.removeFirst()
            let daten = try? Data(contentsOf: URL(fileURLWithPath: pfad))
            try? FileManager.default.removeItem(atPath: pfad)
            // play() returns something for a reason: a piece that never starts
            // must not count as spoken, or the answer disappears in silence.
            if let daten, let s = try? AVAudioPlayer(data: daten), s.play() {
                spieler = s
                stueckBis = Date().addingTimeInterval(s.duration + 5)
                letzteRegung = Date()
                return
            }
        }

        // Nothing left to play. Finished — or is the next piece still being
        // built? A whole minute without any sign means something is stuck, and
        // falling silent is better than counting as "speaking", and therefore
        // deaf, for the rest of the session.
        guard allesGebaut || Date().timeIntervalSince(letzteRegung) > 60 else { return }
        let steckengeblieben = !allesGebaut
        kette?.invalidate(); kette = nil
        redetNoch = false
        if steckengeblieben {
            // Give up properly: raise the run number as well, so nothing that
            // arrives late can still start playing.
            lauf += 1
            abbruchFlagge?.setzen()
            abbruchFlagge = nil
        }
    }

    /// Cuts the text into pieces we can start speaking early. The first one is
    /// deliberately short, so the first words come quickly; after that longer
    /// pieces sound better, because every cut is a small break.
    nonisolated static func haeppchen(_ text: String) -> [String] {
        var saetze: [String] = []
        var jetzt = ""
        for zeichen in text {
            jetzt.append(zeichen)
            let lang = jetzt.count
            // A text without a single full stop would otherwise become one huge
            // piece and the whole wait would be back. So once a piece has grown
            // long we also cut at a comma, and at the next space if it gets
            // really long.
            let notschnitt = (lang >= 120 && ",;:".contains(zeichen))
                || (lang >= 400 && zeichen == " ")
            if ".!?\n".contains(zeichen) || notschnitt {
                saetze.append(jetzt)
                jetzt = ""
            }
        }
        if !jetzt.isEmpty { saetze.append(jetzt) }

        var stuecke: [String] = []
        var puffer = ""
        for satz in saetze {
            puffer += satz
            // Short sentences and things like "z. B." are collected until
            // there is enough of them; a piece of three letters would sound
            // chopped up, not fast.
            let mindestens = stuecke.isEmpty ? 30 : 140
            if puffer.trimmingCharacters(in: .whitespacesAndNewlines).count >= mindestens {
                stuecke.append(puffer.trimmingCharacters(in: .whitespacesAndNewlines))
                puffer = ""
            }
        }
        let rest = puffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty {
            if stuecke.isEmpty { stuecke.append(rest) }
            else { stuecke[stuecke.count - 1] += " " + rest }
        }
        return stuecke.filter { !$0.isEmpty }
    }

    /// Piper measures speed the other way round: a bigger length scale means
    /// a longer, slower utterance. Our slider runs 0.35 (slow) to 0.62 (fast)
    /// with 0.48 in the middle, so dividing gives 1.0 at the midpoint.
    nonisolated static var laengenmass: Double {
        let tempo = UserDefaults.standard.double(forKey: "sprechtempo")
        let t = tempo > 0.1 ? tempo : 0.48
        return min(max(0.48 / t, 0.6), 1.8)
    }

    /// Older builds of piper spell the flag with an underscore, newer ones
    /// with a hyphen, and some accept neither. Rather than guess, we try and
    /// remember what worked — a wrong flag would just fail silently otherwise.
    nonisolated(unsafe) private static var tempoSchalter: String? = "--length-scale"
    nonisolated(unsafe) private static var tempoGeprueft = false

    nonisolated private static func erzeuge(text: String, python: String,
                                            modell: String, ziel: String) -> Bool {
        if lauf(python: python, modell: modell, ziel: ziel, text: text,
                schalter: tempoSchalter) { return true }

        // First failure: work out whether the flag is the problem.
        if !tempoGeprueft {
            tempoGeprueft = true
            for versuch in ["--length_scale", nil] {
                if lauf(python: python, modell: modell, ziel: ziel, text: text,
                        schalter: versuch) {
                    tempoSchalter = versuch
                    return true
                }
            }
        }
        return false
    }

    nonisolated private static func lauf(python: String, modell: String, ziel: String,
                                         text: String, schalter: String?) -> Bool {
        try? FileManager.default.removeItem(atPath: ziel)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        var args = ["-m", "piper", "-m", modell, "-f", ziel]
        if let schalter { args += [schalter, String(format: "%.2f", laengenmass)] }
        p.arguments = args
        let eingabe = Pipe()
        p.standardInput = eingabe
        // These must not be pipes: nobody empties them, and as soon as piper
        // has written a few kilobytes of log into a full pipe it blocks for
        // good — and this thread with it. Hark would then count as "speaking"
        // and stay deaf until it is restarted.
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            eingabe.fileHandleForWriting.write(Data(text.utf8))
            eingabe.fileHandleForWriting.closeFile()
            p.waitUntilExit()
            // Not just "the file is there": piper can exit cleanly and leave a
            // bare header behind. That would count as a finished piece and then
            // vanish without a sound.
            guard p.terminationStatus == 0,
                  let eigenschaften = try? FileManager.default.attributesOfItem(atPath: ziel),
                  let groesse = eigenschaften[.size] as? Int64, groesse > 1024 else { return false }
            return true
        } catch { return false }
    }

    // MARK: - Setting up the engine

    nonisolated static func systemPython() -> String? {
        for pfad in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        where FileManager.default.isExecutableFile(atPath: pfad) { return pfad }
        return nil
    }

    nonisolated static func motorEinrichten(schritt: @escaping @MainActor @Sendable (String) -> Void,
                                            fertig: @escaping @MainActor @Sendable (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            func melde(_ s: String) { Task { @MainActor in schritt(s) } }
            func schluss(_ ok: Bool, _ m: String) { Task { @MainActor in fertig(ok, m) } }
            func lauf(_ b: String) -> Int32 {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-lc", b]
                // Not a pipe: a failing pip install writes a long log, and
                // a full pipe that nobody empties hangs the process for ever.
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                try? p.run(); p.waitUntilExit()
                return p.terminationStatus
            }

            try? FileManager.default.createDirectory(atPath: ordner, withIntermediateDirectories: true)

            guard let sysPy = systemPython() else {
                schluss(false, "Auf diesem Mac fehlt Python. Einmal „xcode-select --install“ ausführen.")
                return
            }
            melde("lege Python-Umgebung an…")
            if lauf("cd '\(ordner)' && '\(sysPy)' -m venv venv") != 0 {
                schluss(false, "Die Python-Umgebung ließ sich nicht anlegen."); return
            }
            melde("lade das Piper-Paket, rund 190 MB — das dauert ein paar Minuten…")
            if lauf("cd '\(ordner)' && ./venv/bin/pip install --quiet --upgrade pip && ./venv/bin/pip install --quiet piper-tts") != 0 {
                schluss(false, "Piper ließ sich nicht installieren."); return
            }
            schluss(true, "Motor bereit — jetzt eine Stimme laden.")
        }
    }

    // MARK: - Downloading a voice, with real progress

    nonisolated static func ladeKlang(_ k: PiperKlang,
                                      fortschritt: @escaping @MainActor @Sendable (Double, String) -> Void,
                                      fertig: @escaping @MainActor @Sendable (Bool, String) -> Void) {
        let basis = "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/\(k.pfad)"
        let modellURL = URL(string: "\(basis)/\(k.kennung).onnx")!
        let infoURL = URL(string: "\(basis)/\(k.kennung).onnx.json")!
        let ziel = modellPfad(k)

        try? FileManager.default.createDirectory(atPath: ordner, withIntermediateDirectories: true)

        let melder = Fortschrittsmelder(anteil: fortschritt) { ok, meldung in
            fertig(ok, meldung)
        }
        melder.starten(modell: modellURL, info: infoURL, ziel: ziel, name: k.name)
    }

    nonisolated static func loescheKlang(_ k: PiperKlang) {
        try? FileManager.default.removeItem(atPath: modellPfad(k))
        try? FileManager.default.removeItem(atPath: modellPfad(k) + ".json")
        if gewaehlt?.kennung == k.kennung { UserDefaults.standard.removeObject(forKey: "piperKlang") }
    }

    nonisolated static func alesEntfernen() {
        try? FileManager.default.removeItem(atPath: ordner)
        UserDefaults.standard.removeObject(forKey: "piperKlang")
    }
}

/// Downloads a voice's two files and reports the progress as it goes.
final class Fortschrittsmelder: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private let anteil: @MainActor @Sendable (Double, String) -> Void
    private let fertig: @MainActor @Sendable (Bool, String) -> Void
    private var ziel = ""
    private var infoURL: URL?
    private var name = ""

    init(anteil: @escaping @MainActor @Sendable (Double, String) -> Void,
         fertig: @escaping @MainActor @Sendable (Bool, String) -> Void) {
        self.anteil = anteil
        self.fertig = fertig
    }

    func starten(modell: URL, info: URL, ziel: String, name: String) {
        self.ziel = ziel
        self.infoURL = info
        self.name = name
        let sitzung = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        sitzung.downloadTask(with: modell).resume()
    }

    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask,
                    didWriteData geschrieben: Int64, totalBytesWritten gesamt: Int64,
                    totalBytesExpectedToWrite erwartet: Int64) {
        guard erwartet > 0 else { return }
        let quote = Double(gesamt) / Double(erwartet)
        let text = "\(name): \(gesamt / 1_048_576) von \(erwartet / 1_048_576) MB"
        let f = anteil
        Task { @MainActor in f(quote, text) }
    }

    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask,
                    didFinishDownloadingTo ort: URL) {
        let f = fertig
        // A 404 or a hotel-wifi login page also arrives as a "successful"
        // download. Without this check it was filed away as a voice, ticked
        // off as ready, and then failed silently on every single sentence.
        if let http = t.response as? HTTPURLResponse, http.statusCode != 200 {
            Task { @MainActor in
                f(false, T.t("Der Server hat die Stimme nicht geliefert (\(http.statusCode)).",
                             "The server did not deliver the voice (\(http.statusCode))."))
            }
            return
        }
        do {
            try? FileManager.default.removeItem(atPath: ziel)
            try FileManager.default.moveItem(at: ort, to: URL(fileURLWithPath: ziel))
        } catch {
            Task { @MainActor in f(false, "Die Stimme ließ sich nicht ablegen.") }
            return
        }
        // the small companion file afterwards
        guard let infoURL else { return }
        let a = anteil
        Task { @MainActor in a(0.99, "fast fertig…") }
        URLSession.shared.dataTask(with: infoURL) { daten, _, _ in
            guard let daten, !daten.isEmpty else {
                // Without its companion the voice is useless — and would sit
                // there as a hundred megabytes that nothing ever tidies up.
                try? FileManager.default.removeItem(atPath: self.ziel)
                Task { @MainActor in
                    f(false, T.t("Die Begleitdatei fehlte.", "The companion file was missing."))
                }
                return
            }
            try? daten.write(to: URL(fileURLWithPath: self.ziel + ".json"))
            Task { @MainActor in f(true, T.t("geladen", "ready")) }
        }.resume()
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError fehler: Error?) {
        // The session holds on to us until it is shut down; without this every
        // download left one behind for the life of the app.
        s.finishTasksAndInvalidate()
        guard let fehler else { return }
        let f = fertig
        Task { @MainActor in f(false, "Laden fehlgeschlagen: \(fehler.localizedDescription)") }
    }
}


/// A little flag that the background thread is allowed to look at, so a
/// cancelled reading stops building pieces nobody will ever hear.
private final class Abbruch: @unchecked Sendable {
    private let sperre = NSLock()
    private var an = false
    var gesetzt: Bool { sperre.lock(); defer { sperre.unlock() }; return an }
    func setzen() { sperre.lock(); an = true; sperre.unlock() }
}
