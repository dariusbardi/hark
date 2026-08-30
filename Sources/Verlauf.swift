// Verlauf.swift — what Hark heard, and where it put it.
//
// Kept in memory only. Quit Hark and it is gone. For an app that listens all
// day that is the honest default: if there is nothing on disk, there is
// nothing to leak, nothing to subpoena and nothing to forget to delete.

import AppKit

struct VerlaufEintrag {
    let zeit: Date
    let text: String
    let ziel: String
}

@MainActor
final class Verlauf: NSObject, NSWindowDelegate, NSTableViewDataSource {

    static let geteilt = Verlauf()

    private(set) var eintraege: [VerlaufEintrag] = []
    private var fenster: NSWindow?
    private var tabelle: NSTableView?
    private var hinweis: NSTextField?

    func merken(_ text: String) {
        let ziel = NSWorkspace.shared.frontmostApplication?.localizedName
            ?? T.t("unbekannt", "unknown")
        eintraege.insert(VerlaufEintrag(zeit: Date(), text: text, ziel: ziel), at: 0)
        if eintraege.count > 100 { eintraege.removeLast() }
        tabelle?.reloadData()
        standZeigen()
    }

    func leeren() {
        eintraege.removeAll()
        tabelle?.reloadData()
        standZeigen()
    }

    // MARK: - Window

    func zeigen() {
        if let fenster {
            NSApp.activate(ignoringOtherApps: true)
            fenster.makeKeyAndOrderFront(nil)
            return
        }
        let f = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        f.title = T.t("Hark — Verlauf", "Hark — History")
        f.isReleasedWhenClosed = false
        f.center()
        f.delegate = self
        f.contentView = inhalt()
        fenster = f
        NSApp.activate(ignoringOtherApps: true)
        f.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ n: Notification) { fenster = nil; tabelle = nil; hinweis = nil }

    private func inhalt() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 420))

        let rollen = NSScrollView(frame: NSRect(x: 0, y: 74, width: 560, height: 346))
        rollen.hasVerticalScroller = true
        rollen.autoresizingMask = [.width, .height]
        rollen.drawsBackground = false

        let t = NSTableView(frame: rollen.bounds)
        t.usesAlternatingRowBackgroundColors = true
        t.rowHeight = 34
        t.headerView = nil
        t.dataSource = self

        let zeit = NSTableColumn(identifier: .init("zeit"))
        zeit.width = 62
        t.addTableColumn(zeit)
        let text = NSTableColumn(identifier: .init("text"))
        text.width = 360
        t.addTableColumn(text)
        let ziel = NSTableColumn(identifier: .init("ziel"))
        ziel.width = 110
        t.addTableColumn(ziel)

        rollen.documentView = t
        tabelle = t
        v.addSubview(rollen)

        let strich = NSBox(frame: NSRect(x: 0, y: 73, width: 560, height: 1))
        strich.boxType = .separator
        strich.autoresizingMask = [.width]
        v.addSubview(strich)

        hinweis = NSTextField(wrappingLabelWithString: "")
        hinweis?.frame = NSRect(x: 20, y: 16, width: 380, height: 44)
        hinweis?.font = .systemFont(ofSize: 10)
        hinweis?.textColor = .tertiaryLabelColor
        hinweis?.autoresizingMask = [.width]
        v.addSubview(hinweis!)

        let leerenKnopf = NSButton(title: T.t("Verlauf leeren", "Clear history"),
                                   target: self, action: #selector(leerenGedrueckt))
        leerenKnopf.frame = NSRect(x: 420, y: 22, width: 122, height: 28)
        leerenKnopf.bezelStyle = .rounded
        leerenKnopf.autoresizingMask = [.minXMargin]
        v.addSubview(leerenKnopf)

        standZeigen()
        return v
    }

    @objc private func leerenGedrueckt() { leeren() }

    private func standZeigen() {
        hinweis?.stringValue = eintraege.isEmpty
            ? T.t("Noch nichts diktiert. Nur im Arbeitsspeicher — beim Beenden von Hark ist der Verlauf weg.",
                  "Nothing dictated yet. Memory only — quitting Hark clears this.")
            : T.t("\(eintraege.count) Einträge. Nur im Arbeitsspeicher — beim Beenden von Hark ist der Verlauf weg. Nichts davon liegt auf der Festplatte.",
                  "\(eintraege.count) entries. Memory only — quitting Hark clears this. None of it is written to disk.")
    }

    // MARK: - Data

    func numberOfRows(in tableView: NSTableView) -> Int { eintraege.count }

    func tableView(_ tableView: NSTableView,
                   objectValueFor spalte: NSTableColumn?, row: Int) -> Any? {
        guard row < eintraege.count else { return nil }
        let e = eintraege[row]
        switch spalte?.identifier.rawValue {
        case "zeit":
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: e.zeit)
        case "ziel": return e.ziel
        default:     return e.text
        }
    }
}
