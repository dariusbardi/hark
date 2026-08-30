// Selbsthilfe.swift — what Hark can do when the Mac is missing something.

import AppKit
import Speech

@MainActor
enum Selbsthilfe {

    /// Opens Apple's own installer dialog for the Command Line Tools.
    /// That is where the Python Piper needs sits. We don't install anything
    /// behind your back — we only open Apple's window, the user has to click.
    static func werkzeugeAnbieten() {
        let a = NSAlert()
        a.messageText = T.t("Auf diesem Mac fehlt Python",
                            "This Mac is missing Python")
        a.informativeText = T.t("""
        Piper braucht Python. Auf dem Mac steckt es in Apples Entwickler-Werkzeugen, \
        einem kostenlosen Paket von Apple selbst.

        Ich kann dir Apples Installationsfenster öffnen — installieren musst du \
        selbst, das dauert ein paar Minuten. Danach hier auf „einrichten“ klicken.

        Die Apple-Stimmen funktionieren auch ohne das alles.
        """, """
        Piper needs Python. On a Mac it comes with Apple’s Command Line Tools, \
        a free package from Apple itself.

        I can open Apple’s installer for you — you do the installing, it takes a \
        few minutes. Then come back and press “install”.

        Apple’s own voices work without any of this.
        """)
        a.addButton(withTitle: T.t("Apples Fenster öffnen", "Open Apple’s installer"))
        a.addButton(withTitle: T.t("Später", "Later"))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["--install"]
        try? p.run()
    }

    /// Apple's speech recognition needs the language model on the device.
    static func spracheAnbieten(_ sprache: String) {
        let a = NSAlert()
        a.messageText = T.t("Diese Sprache liegt noch nicht auf dem Mac",
                            "This language isn’t on your Mac yet")
        a.informativeText = T.t("""
        Hark versteht dich nur mit einem Sprachmodell, das direkt auf dem Gerät liegt \
        — genau deshalb geht nichts ins Netz.

        So holst du es:
        1.  Systemeinstellungen → Tastatur → Diktat.
        2.  Bei „Sprache“ auf Bearbeiten, deine Sprache dazunehmen.
        3.  macOS lädt das Modell im Hintergrund.
        4.  Danach Hark einmal neu starten.

        Vorlesen funktioniert auch ohne.
        """, """
        Hark can only understand you with a language model stored on the device \
        itself — that is exactly why nothing goes online.

        How to get it:
        1.  System Settings → Keyboard → Dictation.
        2.  Next to “Languages”, click Edit and add yours.
        3.  macOS downloads the model in the background.
        4.  Then restart Hark once.

        Reading aloud works without it.
        """)
        a.addButton(withTitle: T.t("Einstellungen öffnen", "Open Settings"))
        a.addButton(withTitle: T.t("Später", "Later"))
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
        }
    }

    /// macOS only applies the Accessibility permission after a restart.
    static func neustartAnbieten() {
        let a = NSAlert()
        a.messageText = T.t("Hark einmal neu starten", "Restart Hark once")
        a.informativeText = T.t("""
        Die Erlaubnis zum Tippen zählt bei macOS erst, wenn das Programm neu \
        gestartet wurde. Ich kann das gleich für dich erledigen.
        """, """
        macOS only applies the typing permission after the app restarts. \
        I can do that for you right now.
        """)
        a.addButton(withTitle: T.t("Jetzt neu starten", "Restart now"))
        a.addButton(withTitle: T.t("Später", "Later"))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        neustart()
    }

    /// Puts a ready-made instruction on the clipboard. Paste it into a Claude
    /// chat once and every answer from then on gets read aloud.
    /// Reachable from the menu and from Settings — someone with a fresh
    /// chat shouldn't have to go hunting for it.
    static func claudeAnleitungKopieren() {
        let d = UserDefaults.standard.string(forKey: "vorleseDatei") ?? ""
        let pfad = d.isEmpty ? Sprecher.standardDatei : (d as NSString).expandingTildeInPath
        let ordner = (pfad as NSString).deletingLastPathComponent

        let text = T.t("""
        Wichtig zuerst: Das hier klappt nur in Cowork, nicht im normalen \
        Claude-Chat. Falls du gerade nicht in einer Cowork-Aufgabe steckst, sag \
        mir das bitte sofort und schreib in zwei Saetzen, wie ich eine aufmache.

        Auf meinem Mac laeuft Hark. Hark schaut staendig in eine Datei und liest \
        laut vor, was darin steht. Die Datei ist:

        \(pfad)

        Bitte mach Folgendes:

        1. Schau nach, ob du in diese Datei schreiben kannst. Wenn nicht, frag \
        mich mit deinem Werkzeug fuer Ordnerzugriff direkt nach genau diesem \
        Ordner: \(ordner) — ich muss dann nur noch bestaetigen. Bitte such nicht \
        lange herum und lass mich erst recht nicht suchen. Falls der Ordner bei \
        dir intern unter einem anderen Pfad haengt als hier steht: das ist \
        derselbe Ordner, nimm einfach deinen eigenen Weg dorthin.

        2. Schreib ab jetzt zu jeder Antwort zusaetzlich eine kurze gesprochene \
        Fassung in diese Datei. Ueberschreib dabei immer den alten Inhalt, haeng \
        nie etwas an.

        3. Die gesprochene Fassung: hoechstens drei Saetze, normale \
        Alltagssprache, keine Aufzaehlungen, keine Dateinamen, keine Pfade, kein \
        Code. Vorgelesen klingt so etwas furchtbar.

        4. Die ausfuehrliche Antwort schreibst du wie immer in den Chat. Die \
        kurze Fassung ist nur zum Hoeren, sie ersetzt nichts.

        5. Mach das bei jeder Antwort, auch bei kurzen, und auch wenn ich nicht \
        extra danach frage — gerade am Ende einer laengeren Arbeit.
        """, """
        First things first: this only works in Cowork, not in a normal Claude \
        chat. If you are not in a Cowork task right now, tell me straight away \
        and explain in two sentences how I open one.

        My Mac runs Hark. Hark keeps watching one file and reads aloud whatever \
        appears in it. The file is:

        \(pfad)

        Please do the following:

        1. Check whether you can write to that file. If you cannot, use your \
        folder-access tool to ask me for exactly this folder: \(ordner) — all I \
        have to do then is confirm. Please do not go hunting for it, and do not \
        make me hunt either. If that folder is mounted under a different path on \
        your side than the one written here, it is the same folder — just use \
        your own route to it.

        2. From now on, with every answer, also write a short spoken version \
        into that file. Always overwrite what was there; never append.

        3. The spoken version: at most three sentences, plain everyday language, \
        no bullet lists, no file names, no paths, no code. Read aloud, those \
        sound dreadful.

        4. Keep writing your full answer in the chat as usual. The short version \
        is only for listening — it replaces nothing.

        5. Do this for every answer, short ones included, and even when I do not \
        ask for it — especially at the end of a longer piece of work.
        """)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        let a = NSAlert()
        a.messageText = T.t("Kopiert — jetzt in Cowork einfuegen",
                            "Copied — now paste it into Cowork")
        a.informativeText = T.t("""
        Der Text liegt in der Zwischenablage.

        So geht es: In der Claude-App auf diesem Mac eine Cowork-Aufgabe starten \
        und den Text einmal mit Befehl V einfuegen. Claude fragt dann von selbst \
        nach dem Ordner, du musst nur bestaetigen.

        Zwei Dinge, an denen es sonst scheitert:

        Der normale Claude-Chat im Browser kann keine Dateien auf deinem Mac \
        schreiben. Es muss Cowork sein, und die Claude-App muss auf diesem Mac \
        offen bleiben — auch dann, wenn du vom Handy aus weiterschreibst.

        In jeder neuen Aufgabe einmal einfuegen. Claude merkt sich das nicht \
        von allein.
        """, """
        The text is on your clipboard.

        Here is how: in the Claude app on this Mac, start a Cowork task and paste \
        the text once with Command V. Claude will then ask for the folder itself \
        — all you do is confirm.

        Two things that otherwise trip it up:

        An ordinary Claude chat in the browser cannot write files on your Mac. \
        It has to be Cowork, and the Claude app has to stay open on this Mac — \
        including when you carry on from your phone.

        Paste it once in every new task. Claude does not remember it by itself.
        """)
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    static func neustart() {
        let pfad = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open '\(pfad)'"]
        try? p.run()
        NSApp.terminate(nil)
    }
}
