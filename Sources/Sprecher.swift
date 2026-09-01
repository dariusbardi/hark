// Sprecher.swift — reads aloud whatever is written into the read-aloud file.
//
// If you want Hark to say something, you just write it into a text file.
// That sounds old-fashioned, but it is exactly right: every program, every
// script and every chat can write to a file — no interface to speak of,
// no sign-in, and Hark never has to put anything online.

import AVFoundation
import NaturalLanguage
import Foundation

@MainActor
final class Sprecher {

    /// Called when speaking switches on or off.
    var beiSprechwechsel: ((Bool) -> Void)?

    private let stimme = AVSpeechSynthesizer()
    private let piper = PiperStimme()
    private var piperRedet = false
    /// Has Piper's audio actually started yet?
    ///
    /// Synthesis takes a second or two before a single sample is played. The
    /// first version cleared the speaking flag during that gap — the ear woke
    /// up, playback began, and Hark transcribed its own voice straight back
    /// into the chat. It literally talked to itself.
    private var piperSpieltSchon = false
    private var piperSeit = Date.distantPast
    private var uhr: Timer?
    private var zuletztGesagt = ""
    private var liestGerade = false
    private var liestSeit = Date.distantPast

    /// Messages waiting their turn, oldest first. With several chats open, a
    /// second answer must not cut the first one off in mid-sentence — it waits.
    private var warteschlange: [(text: String, quelle: String?)] = []

    /// How many are still waiting. The menu shows this.
    var wartende: Int { warteschlange.count }

    private var laeuftGerade: Bool {
        stimme.isSpeaking || piper.redetGerade || piperRedet
    }
    private var spracheGeradeVorher = false

    var redetGerade: Bool { stimme.isSpeaking || piper.redetGerade }

    /// The place where Hark waits for text.
    ///
    /// Documents, not Application Support — even though a file like this
    /// belongs in Application Support. The reason is the other end. The whole
    /// point is that Claude writes into this file, and Claude can only be
    /// handed folders a person would recognise: Documents, Downloads, a
    /// project folder. The Library folder cannot be handed over at all, so a
    /// file in there could never be written to from the outside. A tidy path
    /// nobody can reach is worth less than an untidy one that works.
    static var standardDatei: String {
        let ordner = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Documents/Hark")
        return (ordner as NSString).appendingPathComponent("sprich.txt")
    }

    var datei: String {
        let gespeichert = UserDefaults.standard.string(forKey: "vorleseDatei") ?? ""
        if !gespeichert.isEmpty { return (gespeichert as NSString).expandingTildeInPath }
        return Self.standardDatei
    }

    /// Makes sure the file exists — otherwise nobody knows where to write.
    /// Anyone who used the old spot in the MEGA folder keeps it.
    static func ortVorbereiten() {
        let d = UserDefaults.standard
        if (d.string(forKey: "vorleseDatei") ?? "").isEmpty {
            // Whoever was using an older spot keeps it — moving the file out
            // from under a chat that is set up and working would break it.
            // Only if something really wrote there, though: earlier versions
            // laid down an empty file in Library on every start, and pinning
            // someone to that unreachable place for good would be worse than
            // the move.
            for kandidat in ["MEGA/jarvis/sprich.txt",
                             "Library/Application Support/Hark/sprich.txt"] {
                let alt = (NSHomeDirectory() as NSString).appendingPathComponent(kandidat)
                guard let eigenschaften = try? FileManager.default.attributesOfItem(atPath: alt),
                      let groesse = eigenschaften[.size] as? Int64, groesse > 0 else { continue }
                d.set(alt, forKey: "vorleseDatei")
                break
            }
        }
        let ziel = UserDefaults.standard.string(forKey: "vorleseDatei").flatMap {
            $0.isEmpty ? nil : ($0 as NSString).expandingTildeInPath
        } ?? standardDatei
        let ordner = (ziel as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: ordner, withIntermediateDirectories: true)
        // The postbox: any text file dropped in here is read out once and then
        // removed. One file per message means two chats writing at the same
        // moment cannot overwrite each other, which the single file cannot
        // promise.
        try? FileManager.default.createDirectory(atPath: (ordner as NSString)
            .appendingPathComponent("postfach"), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: ziel) {
            FileManager.default.createFile(atPath: ziel, contents: Data())
        }
    }

    var eingeschaltet: Bool {
        UserDefaults.standard.object(forKey: "vorlesen") == nil
            ? true : UserDefaults.standard.bool(forKey: "vorlesen")
    }

    // MARK: - On and off

    func starten() {
        Self.ortVorbereiten()
        begruessen()
        uhr?.invalidate()
        // Remember the current content at startup without reading it out —
        // otherwise Hark parrots the last message back on every restart.
        zuletztGesagt = (try? String(contentsOfFile: datei, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Four times a second instead of once: the pause before the first
        // word was audible, and looking is cheap now that the reading itself
        // happens off the main thread.
        uhr = Timer.harkUhr(0.25, wiederholt: true) { [weak self] _ in
            Task { @MainActor in self?.nachsehen() }
        }
    }

    /// On the very first launch Hark introduces itself once — and in the
    /// same breath proves the whole read-aloud path holds up.
    /// Hear nothing, and you know at once: something is wrong here.
    private func begruessen() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "begruessungGesprochen") else { return }
        d.set(true, forKey: "begruessungGesprochen")

        let text = T.t("""
        Hallo. Ich bin Hark. Wenn du mich hörst, kann ich dir vorlesen. \
        Sag jetzt einfach mein Weckwort und danach einen Satz — ich tippe ihn \
        dorthin, wo dein Cursor steht.
        """, """
        Hello. I am Hark. If you can hear me, reading aloud works. \
        Now just say my wake word followed by a sentence — I will type it \
        wherever your cursor is.
        """)

        // wait a moment for the menu bar to come up
        Timer.harkUhr(1.5) { [weak self] _ in
            Task { @MainActor in
                try? text.write(toFile: self?.datei ?? Self.standardDatei,
                                atomically: true, encoding: .utf8)
            }
        }
    }

    func stoppen() {
        uhr?.invalidate()
        uhr = nil
        stimme.stopSpeaking(at: .immediate)
    }

    /// What was thrown away when you pressed stop. Postbox messages exist
    /// nowhere else by then — their files are gone — so they go into the
    /// history rather than into nothing.
    var beiVerworfen: (([String]) -> Void)?

    func abbrechen() {
        // "Stop reading" means everything, not just this one sentence.
        if !warteschlange.isEmpty {
            beiVerworfen?(warteschlange.map(\.text))
        }
        warteschlange.removeAll()
        stimme.stopSpeaking(at: .immediate)
        piper.abbrechen()
        piperRedet = false
        piperSpieltSchon = false
    }

    // MARK: - Checking and speaking

    private func nachsehen() {
        // Report the state change so the ear looks away in the meantime
        if piperRedet {
            if piper.redetGerade {
                piperSpieltSchon = true
            } else if piperSpieltSchon {
                piperRedet = false
                piperSpieltSchon = false
            } else if Date().timeIntervalSince(piperSeit) > 45 {
                // Nothing ever started playing. Something further down went
                // wrong — but staying "speaking" for ever would leave the ear
                // deaf for the rest of the session, so we let go.
                piperRedet = false
            }
        }
        let redet = stimme.isSpeaking || piper.redetGerade || piperRedet
        if redet != spracheGeradeVorher {
            spracheGeradeVorher = redet
            beiSprechwechsel?(redet)
        }
        if !redet { naechstes() }

        guard eingeschaltet else { return }
        if liestGerade {
            // A read that has been going for twenty seconds means the file sits
            // on something that stopped answering. Let go rather than never
            // reading anything aloud again.
            guard Date().timeIntervalSince(liestSeit) > 20 else { return }
        }
        liestGerade = true
        liestSeit = Date()
        let pfad = datei

        DispatchQueue.global(qos: .utility).async {
            // Off the main thread on purpose: this file often lives in a folder
            // that syncs to the cloud, and one stalled sync would otherwise
            // bring the whole app to a stop four times a second.
            // Only once the writing has settled. Otherwise we catch half a
            // sentence and read the other half again a moment later. A date in
            // the future — another machine's clock running ahead in a synced
            // folder — cannot be judged, and staying silent for good would be
            // the worse answer, so in that case we read.
            var wirdGeschrieben = false
            if let eigenschaften = try? FileManager.default.attributesOfItem(atPath: pfad),
               let geaendert = eigenschaften[.modificationDate] as? Date {
                let alter = Date().timeIntervalSince(geaendert)
                wirdGeschrieben = alter >= 0 && alter < 0.15
            }
            var gelesen = ""
            if !wirdGeschrieben {
                gelesen = (try? String(contentsOfFile: pfad, encoding: .utf8)) ?? ""
            }
            // The postbox, in the order things were dropped in. Each file is
            // taken away as it is read, so nothing is ever read twice.
            var post: [(String, String?)] = []
            let postfach = (pfad as NSString).deletingLastPathComponent
                + "/postfach"
            if let namen = try? FileManager.default.contentsOfDirectory(atPath: postfach) {
                let dateien = namen
                    .filter { $0.hasSuffix(".txt") && !$0.hasPrefix(".") }
                    .map { (postfach as NSString).appendingPathComponent($0) }
                    .sorted { Self.zeit($0) < Self.zeit($1) }
                for f in dateien {
                    let alter = Date().timeIntervalSince(Self.zeit(f))
                    guard alter < 0 || alter > 0.15 else { continue }   // still being written
                    let roh = (try? String(contentsOfFile: f, encoding: .utf8)) ?? ""
                    try? FileManager.default.removeItem(atPath: f)
                    let t = roh.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { post.append((t, Self.absender(f))) }
                }
            }

            let inhalt = gelesen
            let eingegangen = post
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.liestGerade = false
                for (t, quelle) in eingegangen { self.einreihen(t, quelle: quelle) }

                let text = inhalt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, text != self.zuletztGesagt else { return }
                self.zuletztGesagt = text
                self.einreihen(text, quelle: nil)
            }
        }
    }

    // MARK: - Waiting their turn

    /// Put a message in line. If nothing is being read out, it starts at once.
    private func einreihen(_ text: String, quelle: String?) {
        warteschlange.append((text, quelle))
        if !laeuftGerade { naechstes() }
    }

    /// Take the next one, if there is one and nothing is running.
    private func naechstes() {
        guard !laeuftGerade, !warteschlange.isEmpty else { return }
        let naechste = warteschlange.removeFirst()
        if let quelle = naechste.quelle, !quelle.isEmpty {
            // Say where it came from, otherwise you have no idea which of your
            // chats is talking to you. The language check runs on the message
            // alone: "Bazo schreibt:" is Hark's own German, and on a short
            // English message that prefix is enough to tip the guess.
            sprich(T.t("\(quelle) schreibt: ", "\(quelle) says: ") + naechste.text,
                   pruefText: naechste.text)
        } else {
            sprich(naechste.text)
        }
    }

    nonisolated private static func zeit(_ pfad: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: pfad))?[.modificationDate]
            as? Date ?? .distantPast
    }

    /// The file name is the sender: "bazo.txt" becomes "Bazo". A name that
    /// starts with a digit is a timestamp, not a name — then we say nothing.
    nonisolated private static func absender(_ pfad: String) -> String? {
        let stamm = ((pfad as NSString).lastPathComponent as NSString)
            .deletingPathExtension
        guard let erstes = stamm.first, erstes.isLetter else { return nil }
        return stamm.prefix(1).uppercased() + stamm.dropFirst()
    }

    func sprich(_ text: String) { sprich(text, pruefText: text) }

    /// `pruefText` is what the language check looks at. Usually the same thing
    /// — but not when we put a sender's name in front of the message.
    private func sprich(_ text: String, pruefText: String) {
        Self.merkeGesagt(text)
        // A Piper voice speaks exactly one language. Give it a text in another
        // and you get sounds, not words — so we let Apple take that turn, with
        // a voice that actually fits.
        if let klang = PiperStimme.gewaehlt, Self.passtZu(klang, pruefText) {
            stimme.stopSpeaking(at: .immediate)
            piper.abbrechen()
            piperRedet = true
            piperSpieltSchon = false
            piperSeit = Date()
            // Say so ourselves, otherwise the next check reports it again
            // — and every extra report unbalances the music counter.
            spracheGeradeVorher = true
            beiSprechwechsel?(true)
            piper.sprich(text) { [weak self] geklappt in
                guard let self else { return }
                if geklappt {
                    // Playback has begun. Only from here does "not playing"
                    // really mean finished — before it just meant "still
                    // being made".
                    self.piperSpieltSchon = true
                } else {
                    // Piper is on strike — better to speak with Apple than not at all.
                    self.piperRedet = false
                    self.piperSpieltSchon = false
                    self.mitApple(text, pruefText: pruefText)
                }
            }
            return
        }
        mitApple(text, pruefText: pruefText)
    }

    private func mitApple(_ text: String, pruefText: String) {
        // Piper may still be going: since the language check can send a text to
        // Apple while Piper is mid-sentence, both would otherwise talk at once.
        piper.abbrechen()
        piperRedet = false
        piperSpieltSchon = false
        let ausspruch = AVSpeechUtterance(string: text)
        ausspruch.voice = Self.passendeStimme(fuer: pruefText)
        let tempo = UserDefaults.standard.double(forKey: "sprechtempo")
        ausspruch.rate = tempo > 0.1 ? Float(tempo) : 0.48
        stimme.stopSpeaking(at: .immediate)   // a new answer interrupts the old one
        stimme.speak(ausspruch)
        spracheGeradeVorher = true
        beiSprechwechsel?(true)
    }
}


// MARK: - Recognising our own voice

extension Sprecher {

    /// Hark goes deaf while it is speaking itself. But that only covers its
    /// own loudspeaker — not the case where you play the same answer back from
    /// somewhere else: a voice message, a recording, the same text read by
    /// another program. Then Hark hears its own words as if you had said them,
    /// and types them into your chat.
    ///
    /// So it remembers the last few things it read out, stripped down to bare
    /// letters, and refuses anything that matches. Twenty-five letters in a row
    /// in common is not a coincidence — nobody says that by chance.

    nonisolated static func merkeGesagt(_ text: String) {
        let k = kern(text)
        guard k.count > 25 else { return }
        gehoertes.merke(k)
    }

    nonisolated static func stammtVonUns(_ text: String) -> Bool {
        let k = kern(text)
        guard k.count >= 25 else { return false }
        let alle = gehoertes.alle
        guard !alle.isEmpty else { return false }

        let zeichen = Array(k)
        var start = 0
        while start + 25 <= zeichen.count {
            let stueck = String(zeichen[start..<(start + 25)])
            if alle.contains(where: { $0.contains(stueck) }) { return true }
            start += 5
        }
        return false
    }

    /// Bare letters and single spaces — punctuation and capitals differ
    /// between what we wrote and what the recogniser heard.
    nonisolated private static func kern(_ s: String) -> String {
        s.lowercased()
            .filter { $0.isLetter || $0.isWhitespace }
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}

/// The last few things Hark read out, behind a lock so the recogniser's
/// thread may look at them. It lives outside the class on purpose: Sprecher
/// belongs to the main actor, and a lock that only the main actor may touch
/// is no use to a background thread — that was exactly what the compiler
/// complained about.
private final class Gedaechtnis: @unchecked Sendable {
    private let sperre = NSLock()
    private var texte: [String] = []

    func merke(_ k: String) {
        sperre.lock(); defer { sperre.unlock() }
        texte.append(k)
        if texte.count > 6 { texte.removeFirst() }
    }

    var alle: [String] {
        sperre.lock(); defer { sperre.unlock() }
        return texte
    }
}

private let gehoertes = Gedaechtnis()


// MARK: - The right voice for the language

extension Sprecher {

    /// An English voice reading German is barely words at all — and that is
    /// exactly what happens when the voice is set to one language and the
    /// assistant answers in another. Hark used to read everything with
    /// whatever voice was chosen and never noticed. Now it looks at the text.

    /// nonisolated, weil die beiden Funktionen darunter es auch sind: sie
    /// laufen aus dem Hintergrund. Die Eigenschaft rechnet nichts und haelt
    /// nichts — sie liest nur die Einstellungen, und die duerfen das.
    nonisolated static var stimmeNachSprache: Bool {
        get {
            UserDefaults.standard.object(forKey: "stimmeNachSprache") == nil
                ? true : UserDefaults.standard.bool(forKey: "stimmeNachSprache")
        }
        set { UserDefaults.standard.set(newValue, forKey: "stimmeNachSprache") }
    }

    /// Which language is this? Apple's own recogniser, entirely on the device.
    /// Only trusted when it is reasonably sure: three words can look like
    /// anything, and guessing wrong is worse than not guessing.
    nonisolated static func spracheVon(_ text: String) -> String? {
        let kurz = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kurz.count >= 12 else { return nil }
        let erkenner = NLLanguageRecognizer()
        erkenner.processString(kurz)
        guard let sprache = erkenner.dominantLanguage else { return nil }
        let werte = erkenner.languageHypotheses(withMaximum: 1)
        guard let sicher = werte[sprache], sicher > 0.6 else { return nil }
        return sprache.rawValue
    }

    nonisolated static func passtZu(_ klang: PiperKlang, _ text: String) -> Bool {
        guard stimmeNachSprache, let erkannt = spracheVon(text) else { return true }
        return klang.sprache.hasPrefix(erkannt)
    }

    /// The voice you chose — unless the text is plainly in another language,
    /// and then the best one we have for that language.
    nonisolated static func passendeStimme(fuer text: String) -> AVSpeechSynthesisVoice? {
        let gewaehlt = UserDefaults.standard.string(forKey: "stimme")
            .flatMap { AVSpeechSynthesisVoice(identifier: $0) }
        let ersatz = gewaehlt ?? AVSpeechSynthesisVoice(language: Zuhoersprache.aktuell)

        guard stimmeNachSprache, let erkannt = spracheVon(text) else { return ersatz }
        if let gewaehlt, gewaehlt.language.hasPrefix(erkannt) { return gewaehlt }

        // Without the filter this can land on Zarvox or Bubbles: macOS ships
        // the novelty voices in the same list, and on a Mac with nothing
        // downloaded every voice has the same quality rating. The name is only
        // a tie-break, but it makes the choice repeatable instead of arbitrary.
        let passende = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(erkannt) }
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { a, b in
                let ga = guete(a), gb = guete(b)
                return ga == gb ? a.name < b.name : ga > gb
            }
        return passende.first ?? ersatz
    }

    nonisolated private static func guete(_ s: AVSpeechSynthesisVoice) -> Int {
        if s.voiceTraits.contains(.isPersonalVoice) { return 3 }
        switch s.quality {
        case .premium:  return 2
        case .enhanced: return 1
        default:        return 0
        }
    }
}
