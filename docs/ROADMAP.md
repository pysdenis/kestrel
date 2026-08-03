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
- [x] App uninstaller (bundle + leftovers) — `AppUninstaller`, `kestrel uninstall`.
- [ ] Skutečné provedení Docker/brew prune (mimo vault → vyžaduje explicitní opt-in UX).
**DoD:** ✅ reálně uvolní místo, defaultně dry-run, nic důležitého nesmaže (testy).

## Fáze 2 — Přehled místa 📊 ✅ HOTOVO
- [x] `DiskMap` rekurzivní velikosti (top-level paralelně, symlinky jako listy, depth-limit).
- [x] `DiskUsageReader` (kapacita volume) + `SnapshotStore` denní snapshots + trend + předpověď zaplnění.
- [x] „Co narostlo od minule" diff (`recentChanges`).
- [x] CLI `map` (treemap v terminálu), `snapshot`, `trend`, `diff`.
**DoD:** ✅ vidím, co bere místo, a jak to roste v čase.

## Fáze 3 — Menubar GUI 🖥️ (data ✅, packaging → Fáze 7)
- [x] `StatsCollector`: disk, memory (Mach), CPU load, battery+health/cycles (IOKit),
      Wi-Fi SSID + net counters (getifaddrs/CoreWLAN), volumes — jen veřejná API.
- [x] Mac Health skóre (transparentní vážený průměr, `HealthScorer`) + CLI `stats`.
- [x] SwiftUI `MenuBarExtra` dashboard (`KestrelApp`) s živými dlaždicemi + „Scan" napojený na Fázi 1.
- [ ] Zabalit jako accessory app (LSUIElement bundle, podpis) — Fáze 7. On-access throughput graf.
**DoD:** GUI kompiluje proti živému Core, žádné placebo tlačítko. Běh jako menubar app → po zabalení.

## Fáze 4 — Antivirus 🛡️ (jádro ✅, bundling ClamAV → později)
- [ ] Bundling ClamAV + `freshclam` auto-update — zatím advisory `ClamAVAdapter` (deleguje na lokální clamscan).
- [x] `RuleScanner` (EICAR test + string/SHA-256 pravidla) — čestný, jen reálné nálezy.
- [x] Heuristika (quarantined executables, `LaunchAgentAuditor` osiřelí agenti).
- [x] XProtect/Gatekeeper status reader (`SystemProtectionReader`), quarantine viewer (`QuarantineReader`).
- [ ] On-access watcher (FSEvents na Downloads/Desktop).
**DoD:** ✅ on-demand čestný report („čisto" když čisto, nález s důkazem). On-access zbývá.

## Fáze 5 — Zbytek CleanMyMac sekcí 🧩 (většina ✅)
- [x] SmartScan (orchestrace health + clutter + review + AV) — `SmartScan`, `kestrel smartscan`.
- [x] MaintenanceService (advisory katalog: DNS flush, Spotlight/LaunchServices rebuild, purge, fontcache).
- [x] App Updater (Homebrew casks outdated + Sparkle feed reader) + orphaned data (`OrphanFinder`, `kestrel orphans`).
- [ ] Cloud Cleanup (iCloud Drive/Dropbox/GDrive, offload místo mazání).
- [x] Privacy cleaner (browser cache/history/cookies, review-only) — `PrivacyClassifier`.
- [x] My Activity view nad AuditLog + statistiky úspor (`ActivityReporter`, `kestrel activity`).

## Fáze 6 — Extra & killer funkce 🚀 (většina ✅)
- [x] Power & Wake auditor (`PowerAuditor`, `pmset` assertions) — `kestrel power`.
- [x] Login items & LaunchAgent auditor + osiřelí agenti (`LaunchAgentAuditor`, `kestrel av agents`).
- [ ] Rules engine + `launchd` automatizace.
- [ ] Bandwidth monitor per-app.
- [x] **APFS local snapshots & Time Machine local cleanup** (`LocalSnapshotAuditor`, `tmutil`).
- [x] **Secrets/credential scanner** pro projekty (`SecretsScanner`, `kestrel secrets`).
- [ ] **Apple Shortcuts integrace** (vystavené akce).
- [x] **Homebrew maintenance** (advisory `HomebrewAdapter` + `AppUpdater` outdated casks).
- [ ] Duplicitní & podobné fotky (perceptual hash) — zbývá; Screenshoty ✅ (`ClutterFinder`).
- [x] Old installers/.dmg/.pkg finder (`ClutterFinder`, `kestrel installers`).
- [ ] Config profile / kernel & system extensions audit.
- [x] Sensitive file shredder (`Shredder`, `kestrel shred`, honest o SSD/FileVault).
- [ ] Weekly digest (lokální), menu bar quick actions, „Explain this".

## Fáze 7 — Vydání 📦 (rozpracováno)
- [ ] Vlastní branding + ikony (NE od CleanMyMac) — zatím SF Symbol `bird.fill`.
- [ ] Developer ID podpis + notarizace + stapling — postup v `docs/RELEASE.md`.
- [x] App bundle skript (`scripts/build-app.sh` → `dist/Kestrel.app`, ad-hoc podpis, LSUIElement).
- [ ] Sparkle auto-update NEBO GitHub Releases — `AppUpdater.sparkleFeed` už čte `SUFeedURL`.
- [x] LICENSE (MIT), README pro veřejnost s reálným použitím. Zbývají screenshoty.
- [ ] Rozhodnout model: čistě OSS / OSS + placené buildy / donationware.

---

## Návrh prvního sprintu (co říct Claudovi)
> „Rozjeď Fázi 0: založ SPM workspace, naimplementuj VaultService a AuditLog
> s testy na temp adresářích a přidej CLI příkaz `kestrel vault list/undo`.
> Dodržuj invarianty z CLAUDE.md."
