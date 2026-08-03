# Roadmap

Postupuj fázově. Nezačínej vyšší fázi, dokud nižší nestojí a nemá testy.
Pořadí je záměrné: bezpečnostní základ → hodnota → efekt.

## Fáze 0 — Základ a bezpečnost 🔒 ✅ HOTOVO (2026-08-03)
Cíl: infrastruktura, na které stojí vše ostatní. Bez UI.
- [x] SPM projekt: `KestrelCore` (lib), `kestrel-cli` (exe), `kestrel-tests` (runner).
- [x] `FileEntry`, `Category`, `Confidence`, `ClassifiedEntry`, `CleanupPlan` modely.
- [x] `VaultService` (beginSession/move/undo/listSessions/purge) + testy.
- [x] `AuditLog` (JSON-lines, append-only).
- [x] Scan→Classify→Plan→Apply pipeline s dry-run defaultem (`CleanupExecutor`).
- [x] CLI: `scan`, `clean [--apply]`, `vault list/undo/purge`, `audit`.
- [x] 22 testů zelených (manuální runner; XCTest verze v `Tests/` pro Xcode).
**Definition of done:** ✅ ověřeno end-to-end — apply přesune do vaultu, undo vrátí
i s obsahem, audit zapsán, dry-run nic nesmaže.

> Pozn.: XCTest (`swift test`) vyžaduje plný Xcode. Bez něj: `swift run kestrel-tests`.

## Fáze 1 — Čisticí jádro + CLI 🧹 (rozpracováno)
- [x] Classifiery: safe cache/logs (per-app + dev-tool cache), dev-artefakty
      (node/Xcode/Python/Rust/Java/Gradle/CocoaPods) s potvrzením přes project marker,
      duplicity (size→partial hash→full hash), velké & staré soubory (konfig. prahy).
- [x] `SafetyGuard` blacklist (klíče, klíčenky, `.git`, Photos, systémové cesty)
      jako finální brána v planneru + review-only kategorie (dupes/large).
- [x] `ScanCoordinator` — jeden rekurzivní průchod, najde i vnořené dev-artefakty.
- [x] Docker cleanup adapter (`docker system df` náhled, advisory — mimo vault).
- [x] Homebrew adapter (`brew cleanup --dry-run` náhled, advisory — mimo vault).
- [x] `kestrel clean --category cache|logs|dev|dupes|large [--apply]` + breakdown.
- [ ] App uninstaller (bundle + leftovers).
- [ ] Skutečné provedení Docker/brew prune (mimo vault → vyžaduje explicitní opt-in UX).
**DoD:** reálně uvolní místo na mém Macu, defaultně dry-run, nic důležitého nesmaže (testy).
Stav: 90 testů zelených (`swift run kestrel-tests`). Zbývá app uninstaller.

## Fáze 2 — Přehled místa 📊
- [ ] `DiskMap` rekurzivní velikosti (paralelně).
- [ ] Denní snapshots + trend + předpověď zaplnění.
- [ ] „Co narostlo od minule" diff.
- [ ] CLI `map` (treemap v terminálu).
**DoD:** vidím, co bere místo, a jak to roste v čase.

## Fáze 3 — Menubar GUI 🖥️
- [ ] `NSStatusItem` + `NSPopover` + SwiftUI dashboard.
- [ ] Živé dlaždice: disk, memory pressure, battery+health, CPU, Wi-Fi throughput, volumes.
- [ ] Mac Health skóre (rozklikací, transparentní).
- [ ] Napojení „Free Up" na Fázi 1, „Přehled" na Fázi 2.
**DoD:** funkční menubar app s živými daty, žádné placebo tlačítko.

## Fáze 4 — Antivirus 🛡️
- [ ] Bundling ClamAV + `freshclam` auto-update.
- [ ] YARA scanner + startovní sada pravidel.
- [ ] Heuristika (nepodepsané, Downloads-origin, LaunchAgents audit).
- [ ] XProtect/Gatekeeper status reader, quarantine viewer.
- [ ] On-access watcher (FSEvents na Downloads/Desktop).
**DoD:** on-demand i on-access sken, čestný report, žádné strašení.

## Fáze 5 — Zbytek CleanMyMac sekcí 🧩
- [ ] SmartScan (jednotlačítková orchestrace clean+stats+AV+updates).
- [ ] MaintenanceService (periodic skripty, DNS flush, Spotlight/LaunchServices rebuild, purgeable).
- [ ] App Updater (Homebrew casks + Sparkle feedy) + Reset app + orphaned data.
- [ ] Cloud Cleanup (iCloud Drive/Dropbox/GDrive, offload místo mazání).
- [ ] Privacy cleaner (browser history/cookies/trackery, recent items).
- [ ] My Activity view nad AuditLog + statistiky úspor.

## Fáze 6 — Extra & killer funkce 🚀
- [ ] Power & Wake auditor (pmset assertions, wake reasons).
- [ ] Login items & LaunchAgent auditor (+ osiřelí agenti).
- [ ] Rules engine + `launchd` automatizace.
- [ ] Bandwidth monitor per-app.
- [ ] **APFS local snapshots & Time Machine local cleanup** (`tmutil`).
- [ ] **Secrets/credential scanner** pro projekty.
- [ ] **Apple Shortcuts integrace** (vystavené akce).
- [ ] **Homebrew maintenance.**
- [ ] Duplicitní & podobné fotky (perceptual hash) + Screenshoty.
- [ ] Old installers/.dmg/.pkg, broken items finder.
- [ ] Config profile / kernel & system extensions audit.
- [ ] Sensitive file shredder (FileVault-aware).
- [ ] Weekly digest (lokální), menu bar quick actions, „Explain this".

## Fáze 7 — Vydání 📦
- [ ] Vlastní branding + ikony (NE od CleanMyMac).
- [ ] Developer ID podpis + notarizace + stapling.
- [ ] Sparkle auto-update (open-source) NEBO GitHub Releases.
- [ ] LICENSE, README pro veřejnost, screenshoty.
- [ ] Rozhodnout model: čistě OSS / OSS + placené buildy / donationware.

---

## Návrh prvního sprintu (co říct Claudovi)
> „Rozjeď Fázi 0: založ SPM workspace, naimplementuj VaultService a AuditLog
> s testy na temp adresářích a přidej CLI příkaz `kestrel vault list/undo`.
> Dodržuj invarianty z CLAUDE.md."
