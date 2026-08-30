// Sprache.swift — the interface in German and English.
//
// No key system, no translation files: both versions sit right next to
// each other in the code. Sounds clumsy, but it has one big
// advantage — you can never forget to update a translation, because it
// is right there in the same breath.

import Foundation

enum T {

    /// "auto", "de" or "en"
    static var eingestellt: String {
        UserDefaults.standard.string(forKey: "oberflaeche") ?? "auto"
    }

    static var aktiv: String {
        let g = eingestellt
        if g == "de" || g == "en" { return g }
        let system = Locale.preferredLanguages.first ?? "en"
        return system.hasPrefix("de") ? "de" : "en"
    }

    static var istDeutsch: Bool { aktiv == "de" }

    /// t("Zuhören pausieren", "Pause listening")
    static func t(_ de: String, _ en: String) -> String { istDeutsch ? de : en }
}

/// How Hark knows which language to listen in.
enum Zuhoersprache {

    static let unterstuetzt = ["de-DE", "en-US", "en-GB", "fr-FR", "es-ES",
                               "it-IT", "nl-NL", "pl-PL", "pt-BR", "tr-TR"]

    /// Whatever the Mac speaks — and if we can't do that one, English.
    /// This used to be hard-wired to German. Wrong for everyone but Darius:
    /// an app that understands an American in German feels broken.
    static var standard: String {
        let system = Locale.preferredLanguages.first ?? "en-US"
        // exact match, e.g. "de-DE"
        if let genau = unterstuetzt.first(where: { $0.caseInsensitiveCompare(system) == .orderedSame }) {
            return genau
        }
        // same language, other region: "de-AT" -> "de-DE", "en-AU" -> "en-US"
        let kurz = String(system.prefix(2)).lowercased()
        if let nah = unterstuetzt.first(where: { $0.hasPrefix(kurz) }) {
            return nah
        }
        return "en-US"
    }

    /// The language that was set, or else the system's.
    static var aktuell: String {
        let g = UserDefaults.standard.string(forKey: "sprache") ?? ""
        return g.isEmpty ? standard : g
    }
}


// MARK: - Clocks that keep running

extension Timer {

    /// Like `scheduledTimer`, but it also keeps running while the menu bar
    /// menu is open or a dialog is up. The usual run-loop mode stops dead in
    /// both cases — and a pause clock that stops mid-sentence loses the
    /// sentence, which is exactly what used to happen.
    @discardableResult
    static func harkUhr(_ zeit: TimeInterval, wiederholt: Bool = false,
                        _ tue: @escaping @Sendable (Timer) -> Void) -> Timer {
        let uhr = Timer(timeInterval: zeit, repeats: wiederholt, block: tue)
        RunLoop.main.add(uhr, forMode: .common)
        return uhr
    }
}
