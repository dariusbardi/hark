// Musik.swift — pause the music while Hark listens or speaks, then put it back.
//
// Deliberately narrow: we ask Music and Spotify what they are doing and pause
// only what was actually playing. The blunt alternative — sending the global
// play/pause key — would start music on a silent Mac, because there is no way
// to ask "is anything playing?" first. Better to cover two players correctly
// than every player wrongly.
//
// Everything here runs off the main thread. The first version did not, and
// that was a real bug: asking two apps a question over Apple Events takes a
// few hundred milliseconds, and doing that on the main thread while speech
// recognition is running delays the very callbacks that decide when your
// sentence ended. The symptom was sentences being cut off after two words.

import AppKit

@MainActor
enum Musik {

    private static let spieler = ["Music", "Spotify"]
    private static let schlange = DispatchQueue(label: "studio.bazo.hark.musik")
    private static var angehalten: [String] = []
    private static var tiefe = 0

    static var eingeschaltet: Bool {
        get {
            UserDefaults.standard.object(forKey: "musikPausieren") == nil
                ? true : UserDefaults.standard.bool(forKey: "musikPausieren")
        }
        set { UserDefaults.standard.set(newValue, forKey: "musikPausieren") }
    }

    /// Pause whatever is playing. Nested calls are counted, so listening and
    /// speaking back to back does not resume the music in between.
    /// `fertig` says whether music was actually stopped. Asking two apps over
    /// Apple Events takes a moment, and that moment is the only time anyone
    /// has to wait for us — so the caller can say when it is over.
    static func anhalten(fertig: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        guard eingeschaltet else { fertig?(false); return }
        tiefe += 1
        guard tiefe == 1 else { fertig?(false); return }

        let laufende = spieler.filter(laeuft)
        angehalten = []
        guard !laufende.isEmpty else { fertig?(false); return }

        schlange.async {
            var pausiert: [String] = []
            for name in laufende {
                if skript("tell application \"\(name)\" to player state as string") == "playing" {
                    _ = skript("tell application \"\(name)\" to pause")
                    pausiert.append(name)
                }
            }
            Task { @MainActor in
                // Only remember them if nobody resumed in the meantime.
                if tiefe > 0 { angehalten = pausiert }
                else { for n in pausiert { schlange.async { _ = skript("tell application \"\(n)\" to play") } } }
                fertig?(tiefe > 0 && !pausiert.isEmpty)
            }
        }
    }

    /// Resume exactly what we paused, and nothing else.
    static func weiter() {
        guard tiefe > 0 else { return }
        tiefe -= 1
        guard tiefe == 0 else { return }

        let zurueck = angehalten
        angehalten = []
        guard !zurueck.isEmpty else { return }
        schlange.async {
            for name in zurueck { _ = skript("tell application \"\(name)\" to play") }
        }
    }

    /// Forget everything — used when the feature is switched off mid-pause,
    /// so the music does not stay silent forever.
    static func aufloesen() {
        if tiefe > 0 { tiefe = 1; weiter() }
    }

    /// The same, but here and now instead of on the side queue. Only for
    /// quitting: the app is about to be gone, and a block handed to another
    /// queue would never run — the music would stay off with nobody left to
    /// press play. Half a second of delay on the way out is worth that.
    static func sofortAufloesen() {
        guard tiefe > 0 else { return }
        tiefe = 0
        let zurueck = angehalten
        angehalten = []
        for name in zurueck { _ = skript("tell application \"\(name)\" to play") }
    }

    // MARK: - Helpers

    /// Cheap and main-thread-safe: just a look at the process list.
    private static func laeuft(_ name: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.localizedName == name
                || $0.bundleIdentifier?.lowercased().hasSuffix(name.lowercased()) == true
        }
    }

    /// Never call this from the main thread.
    nonisolated fileprivate static func skript(_ text: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", text]
        let raus = Pipe()
        p.standardOutput = raus
        p.standardError = FileHandle.nullDevice   // nobody empties it, so no pipe
        do {
            try p.run()
            let daten = raus.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(data: daten, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }
}


// MARK: - Volume

/// Turning the Mac up while Hark speaks, and putting it back afterwards.
///
/// The reason is a hard limit: an app can never be louder than the Mac it runs
/// on. Turning Hark up does nothing once it is already at full volume. So if
/// you want to hear Hark over music that is comfortable to listen to, the only
/// honest way is to move the Mac's own volume for those few seconds — and to
/// put it back exactly where it was.
@MainActor
enum Lautstaerke {

    private static let schlange = DispatchQueue(label: "studio.bazo.hark.lautstaerke")
    private static var vorher: Int?
    private static var angehoben = false

    /// 0 means: leave the volume alone. Anything else is a percentage.
    static var ziel: Int {
        get { UserDefaults.standard.integer(forKey: "vorleseLautstaerke") }
        set { UserDefaults.standard.set(min(max(newValue, 0), 100), forKey: "vorleseLautstaerke") }
    }

    static func anheben() {
        let z = ziel
        guard z > 0, !angehoben else { return }
        angehoben = true
        schlange.async {
            let alt = lesen()
            setzen(z)
            Task { @MainActor in
                if angehoben {
                    vorher = alt
                } else {
                    // It was over before we even got here. Put it straight back.
                    schlange.async { setzen(alt) }
                }
            }
        }
    }

    static func zurueck() {
        guard angehoben else { return }
        angehoben = false
        guard let alt = vorher else { return }   // the block above puts it back itself
        vorher = nil
        schlange.async { setzen(alt) }
    }

    nonisolated private static func lesen() -> Int {
        Int(Musik.skript("output volume of (get volume settings)")) ?? -1
    }

    nonisolated private static func setzen(_ wert: Int) {
        guard wert >= 0, wert <= 100 else { return }   // -1 means: could not read it
        _ = Musik.skript("set volume output volume \(wert)")
    }
}
