// Neuigkeit.swift — asking GitHub whether a newer Hark exists.
//
// This is the only place in Hark that talks to the internet, and it stays
// off until you switch it on. Even then it asks for exactly one thing —
// the newest release — and sends nothing along: no identifier, no version
// number, no count of anything. GitHub learns that somebody asked, and an
// IP address, the same as opening the page in a browser.
//
// It only ever tells you. It never installs anything. An app that replaces
// itself with something it downloaded is precisely how bad code travels,
// and without a paid Developer ID there is no signature to check the
// download against. So: a note, a button, and your decision.

import AppKit

@MainActor
enum Neuigkeit {

    private static let quelle =
        "https://api.github.com/repos/dariusbardi/hark/releases/latest"

    static var eingeschaltet: Bool {
        get { UserDefaults.standard.bool(forKey: "updatePruefen") }   // off unless asked for
        set { UserDefaults.standard.set(newValue, forKey: "updatePruefen") }
    }

    private static var zuletzt: Date {
        get { UserDefaults.standard.object(forKey: "updateZuletzt") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "updateZuletzt") }
    }

    /// At startup. Silent unless there really is something new, and at most
    /// once a day — nobody wants a dialog every time they log in.
    static func beiGelegenheitSchauen() {
        guard eingeschaltet, Date().timeIntervalSince(zuletzt) > 86_400 else { return }
        schauen(nurWennNeu: true)
    }

    /// From the menu. Says something either way, so the click is never a dud.
    static func jetztSchauen() { schauen(nurWennNeu: false) }

    private static func schauen(nurWennNeu: Bool) {
        zuletzt = Date()
        guard let url = URL(string: quelle) else { return }
        var anfrage = URLRequest(url: url)
        anfrage.timeoutInterval = 15
        anfrage.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: anfrage) { daten, antwort, _ in
            var gefunden: String?
            var adresse: String?
            if let daten,
               (antwort as? HTTPURLResponse)?.statusCode == 200,
               let obj = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any] {
                gefunden = (obj["tag_name"] as? String)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                adresse = obj["html_url"] as? String
            }
            let neu = gefunden
            let wohin = adresse
            Task { @MainActor in melden(neu, wohin, nurWennNeu: nurWennNeu) }
        }.resume()
    }

    private static func melden(_ neu: String?, _ adresse: String?, nurWennNeu: Bool) {
        guard let neu, !neu.isEmpty else {
            if !nurWennNeu {
                sagen(T.t("GitHub war gerade nicht erreichbar",
                          "Could not reach GitHub just now"),
                      T.t("Kein Internet, oder GitHub hat nicht geantwortet. Probier es später nochmal.",
                          "No connection, or GitHub did not answer. Try again later."))
            }
            return
        }
        guard hoeher(neu, als: harkVersion) else {
            if !nurWennNeu {
                sagen(T.t("Du hast die neueste Fassung", "You are up to date"),
                      T.t("Hark \(harkVersion) ist aktuell.",
                          "Hark \(harkVersion) is the latest there is."))
            }
            return
        }

        let a = NSAlert()
        a.messageText = T.t("Hark \(neu) ist da", "Hark \(neu) is out")
        a.informativeText = T.t("""
        Du hast \(harkVersion). Auf GitHub liegt die neue Fassung, und daneben \
        steht, was sich geändert hat.

        Herunterladen und einsetzen musst du selbst — Hark tauscht sich nicht \
        von allein aus.
        """, """
        You have \(harkVersion). The new one is on GitHub, along with a note on \
        what changed.

        Downloading and installing is up to you — Hark does not replace itself.
        """)
        a.addButton(withTitle: T.t("Ansehen", "Take a look"))
        a.addButton(withTitle: T.t("Später", "Later"))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        if let adresse, let u = URL(string: adresse) { NSWorkspace.shared.open(u) }
    }

    private static func sagen(_ titel: String, _ text: String) {
        let a = NSAlert()
        a.messageText = titel
        a.informativeText = text
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// Compared number by number, not as text — otherwise "1.10" would look
    /// older than "1.9", and that mistake only shows up much later.
    static func hoeher(_ a: String, als b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let links = i < x.count ? x[i] : 0
            let rechts = i < y.count ? y[i] : 0
            if links != rechts { return links > rechts }
        }
        return false
    }
}
