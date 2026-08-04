import Foundation

/// Which language the UI shows. `system` follows the Mac's language (Czech → Czech,
/// otherwise English). Kestrel ships its own lightweight table (no Xcode string catalog /
/// bundled `.lproj` needed, which the ad-hoc packaging can't produce). Anything not in the
/// table falls back to its English source string, so the UI is never blank.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, czech, english
    var id: String { rawValue }
    var label: String {
        switch self { case .system: return "System"; case .czech: return "Čeština"; case .english: return "English" }
    }
}

enum Localization {
    static func translate(_ en: String, to lang: AppLanguage) -> String {
        guard lang == .czech else { return en }
        return cs[en] ?? en
    }

    /// English source → Czech. Covers the visible chrome (navigation, section headers,
    /// primary actions, verdicts). Extend as more of the deep UI gets localized.
    static let cs: [String: String] = [
        // Sidebar + groups
        "Smart Care": "Smart Care",
        "Dashboard": "Přehled",
        "Cleanup": "Úklid",
        "Space": "Místo",
        "Energy": "Energie",
        "Security": "Zabezpečení",
        "Applications": "Aplikace",
        "Permissions": "Oprávnění",
        "Tools": "Nástroje",
        "Assistant": "Asistent",
        "Activity": "Aktivita",
        "My Activity": "Moje aktivita",
        "Settings": "Nastavení",
        "Monitor": "Sledování",
        "Maintain": "Údržba",
        "Intelligence": "Inteligence",
        "Commands": "Příkazy",

        // Section subtitles
        "One honest pass across cleanup, protection and malware": "Jeden poctivý průchod: úklid, ochrana a malware",
        "Live health, storage forecast and protection at a glance": "Živý stav, předpověď místa a ochrana na první pohled",
        "Preview first — nothing is deleted, items move to the vault": "Nejdřív náhled — nic se nemaže, položky jdou do trezoru",
        "Where your storage is going": "Kam se ztrácí místo na disku",
        "What's using power — right now and over the last 24 hours": "Co spotřebovává energii — teď i za posledních 24 hodin",
        "Honest, evidence-based checks — no scare tactics": "Poctivé kontroly podložené důkazy — žádné strašení",
        "Uninstall cleanly (bundle + leftovers → vault) and see what has updates": "Čisté odinstalování (aplikace + zbytky → trezor) a přehled aktualizací",
        "Which apps hold Camera, Microphone, Full Disk Access and more — read-only": "Které aplikace mají kameru, mikrofon, plný přístup k disku a další — jen ke čtení",
        "One-click cleanup tools and developer utilities": "Nástroje na úklid jedním klikem a vývojářské utility",
        "What Kestrel has done, and how your Mac is doing — honest, from the audit log": "Co Kestrel udělal a jak se Macu daří — poctivě z auditního logu",
        "Preferences, the vault, and where Kestrel stores things": "Předvolby, trezor a kam Kestrel ukládá data",

        // Dashboard / health
        "Mac Health": "Stav Macu",
        "Free up space": "Uvolnit místo",
        "Run Smart Care": "Spustit Smart Care",
        "Get insight": "Získat postřeh",
        "Storage forecast": "Předpověď místa",
        "Protection": "Ochrana",
        "Great": "Skvělé",
        "Good": "Dobré",
        "Fair": "Ucházející",
        "Needs attention": "Vyžaduje pozornost",
        "Your Mac is in great shape": "Tvůj Mac je ve skvělé kondici",
        "Your Mac is running well": "Tvůj Mac šlape dobře",
        "A little upkeep would help": "Trocha údržby by pomohla",
        "Some things need attention": "Něco vyžaduje pozornost",

        // Common actions / labels
        "Scan": "Skenovat",
        "Rescan": "Znovu skenovat",
        "Clean": "Vyčistit",
        "Restore": "Obnovit",
        "Cancel": "Zrušit",
        "Choose…": "Vybrat…",
        "Review": "Zkontrolovat",
        "Review all": "Zkontrolovat vše",
        "Run": "Spustit",
        "Run again": "Spustit znovu",
        "Uninstall": "Odinstalovat",
        "Reset": "Resetovat",
        "Clear": "Vymazat",
        "Copy digest": "Kopírovat souhrn",
        "Get Mac Health": "Zjistit stav Macu",
        "Manage vault": "Spravovat trezor",
        "Open Security": "Otevřít Zabezpečení",
        "Open Privacy settings": "Otevřít nastavení soukromí",
        "Free up memory": "Uvolnit paměť",
        "Explain": "Vysvětlit",
        "Clean dev junk": "Vyčistit dev balast",

        // Settings
        "Preferences": "Předvolby",
        "Launch at login": "Spustit při přihlášení",
        "Start Kestrel automatically when you log in.": "Spustit Kestrel automaticky po přihlášení.",
        "Low-space notifications": "Upozornění na málo místa",
        "A local alert when the disk is nearly full. Nothing leaves this Mac.": "Lokální upozornění, když je disk skoro plný. Nic neopustí tento Mac.",
        "Vault retention": "Doba uchování v trezoru",
        "Language": "Jazyk",
        "Choose the interface language. System follows your Mac.": "Vyber jazyk rozhraní. Systém následuje nastavení Macu.",
        "days": "dní",
        "How long cleaned items stay restorable before they can be purged.": "Jak dlouho zůstanou vyčištěné položky obnovitelné, než je lze trvale smazat.",
        "Vault": "Trezor",
        "Safety": "Bezpečnost",
        "Version": "Verze",

        // Smart Care
        "Run Smart Care": "Spustit Smart Care",
        "Smart Care complete": "Smart Care dokončeno",
        "Running Smart Care…": "Probíhá Smart Care…",
        "Reclaimable space": "Uvolnitelné místo",
        "macOS protection": "Ochrana macOS",
        "Downloads malware scan": "Sken malwaru ve Stažených",
        "Health": "Stav",
        "Malware": "Malware",
        "Waiting": "Čeká",
        "Scanning…": "Skenuji…",
        "Done": "Hotovo",

        // Categories
        "CATEGORY": "KATEGORIE",
        "Everything safe": "Vše bezpečné",
        "Dev artifacts": "Dev artefakty",
        "Caches": "Cache",
        "Logs": "Logy",
        "Duplicates": "Duplikáty",
        "Large & old": "Velké a staré",
        "Privacy": "Soukromí",
    ]
}
