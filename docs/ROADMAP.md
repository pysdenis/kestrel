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
- [~] ClamAV: `av deep` (full sken) + `av update` (freshclam) přes lokální clamav (brew); bundling binárek do repa nepraktické.
- [x] `RuleScanner` (EICAR test + string/SHA-256 pravidla) — čestný, jen reálné nálezy.
- [x] Heuristika (quarantined executables, `LaunchAgentAuditor` osiřelí agenti).
- [x] XProtect/Gatekeeper status reader (`SystemProtectionReader`), quarantine viewer (`QuarantineReader`).
- [x] On-access watcher (FSEvents na Downloads/Desktop) — `OnAccessWatcher`, `kestrel av watch`.
**DoD:** ✅ on-demand i on-access čestný report („čisto" když čisto, nález s důkazem).

## Fáze 5 — Zbytek CleanMyMac sekcí 🧩 (většina ✅)
- [x] SmartScan (orchestrace health + clutter + review + AV) — `SmartScan`, `kestrel smartscan`.
- [x] MaintenanceService (advisory katalog: DNS flush, Spotlight/LaunchServices rebuild, purge, fontcache).
- [x] App Updater (Homebrew casks outdated + Sparkle feed reader) + orphaned data (`OrphanFinder`, `kestrel orphans`).
- [x] Cloud Cleanup (`CloudOffloadFinder`, `kestrel cloud` — offload iCloud přes brctl, advisory).
- [x] Privacy cleaner (browser cache/history/cookies, review-only) — `PrivacyClassifier`.
- [x] My Activity view nad AuditLog + statistiky úspor (`ActivityReporter`, `kestrel activity`).

## Fáze 6 — Extra & killer funkce 🚀 (většina ✅)
- [x] Power & Wake auditor (`PowerAuditor`, `pmset` assertions) — `kestrel power`.
- [x] Login items & LaunchAgent auditor + osiřelí agenti (`LaunchAgentAuditor`, `kestrel av agents`).
- [x] Rules engine (`RulesEngine`, `kestrel rules list/run`); `launchd` automatizace zbývá.
- [ ] Bandwidth monitor per-app.
- [x] **APFS local snapshots & Time Machine local cleanup** (`LocalSnapshotAuditor`, `tmutil`).
- [x] **Secrets/credential scanner** pro projekty (`SecretsScanner`, `kestrel secrets`).
- [ ] **Apple Shortcuts integrace** (vystavené akce).
- [x] **Homebrew maintenance** (advisory `HomebrewAdapter` + `AppUpdater` outdated casks).
- [ ] Duplicitní & podobné fotky (perceptual hash) — zbývá; Screenshoty ✅ (`ClutterFinder`).
- [x] Old installers/.dmg/.pkg finder (`ClutterFinder`, `kestrel installers`).
- [~] System extensions audit (`SystemExtensionAuditor`, `kestrel sysext`); config profiles zbývá.
- [x] Sensitive file shredder (`Shredder`, `kestrel shred`, honest o SSD/FileVault).
- [x] **AI asistent (Gemini, opt-in)** — „Explain this", cleanup summary, ask (metadata-only):
      `GeminiClient` + `AIAssistant`, CLI `ask`/`explain`/`advise`, GUI Assistant sekce.
- [ ] Weekly digest (lokální), menu bar quick actions.

## Fáze 8 — GUI 2.0 🎨 (rozpracováno)
- [x] Oprava zobrazení místa (purgeable se nepočítá jako volné; sedí s `df`/Finder).
- [x] Speed test internetu na kliknutí (`SpeedTest`, Cloudflare endpoint, `kestrel speedtest`).
- [x] Moderní design: `DesignSystem` (material karty, health ring, metric tiles, bars), redesign menubar popoveru.
- [x] Plné okno (`Window` scéna) se sidebarem: Dashboard · Cleanup · Space · Energy · Security · Tools · Activity · Settings — napojené na Core; Cleanup reálně přesouvá do vaultu, přepínání accessory↔regular (Dock).
- [x] **Energy modul**: co bere baterku teď (`EnergyMonitor`, top consumers) + za 24h (`EnergyLog`), ukončení procesu (`ProcessController`, SIGTERM, guard pid>1). CLI `energy`.
- [x] Rozklikávací dlaždice v popoveru (Disk/Memory/CPU/Battery → zkrácený detail).
- [x] Animovaný speed gauge (sweep při měření + count-up výsledku).
- [x] Živý graf síťového throughputu (sparkline) na dashboardu.
- [x] Idle efektivita: polling jen když je UI vidět (idle 0 % CPU); adaptivní paleta 1:1 s referencí.
- [x] Live odhad baterie z okamžitého proudu (AppleSmartBattery), time-left přímo na kartě.
- [x] Interaktivní treemap ve Space (`Treemap` squarified + drill-down breadcrumb).

## Fáze 9 — AI & automatizace 🤖 (rozpracováno)
Detaily viz brainstorm; AI je vždy opt-in a posílá jen metadata (invariant #7).
- [x] **AI asistent (Gemini)**: `GeminiClient` + `AIAssistant`, CLI `ask`/`explain`/`advise`, GUI Assistant sekce.
- [x] **AI „druhý názor" před `apply`** (`AIAssistant.review`, CLI `clean --review`, GUI tlačítko).
- [x] **AI vysvětlení bezpečnostního nálezu** (`AIAssistant.explainFinding`, `kestrel av explain`).
- [x] **Přirozený jazyk → rule** (`AIAssistant.suggestRule`, `kestrel rules suggest`) — AI navrhne, uživatel potvrdí.
- [x] **Weekly digest** (`DigestReporter`, `kestrel digest` — úspory + trend + co narostlo).
- [x] **`launchd` automatizace** pro rules (`RulesScheduler`, `kestrel rules install-agent`).
- [ ] **Perceptuální hash** na podobné fotky + seskupení screenshotů.
- [x] **System extensions audit** (`SystemExtensionAuditor`, `kestrel sysext`); config profiles zbývá.
- [x] **Lokální notifikace** (`Notifier`, UserNotifications) — málo místa (opt-in toggle v Settings, bundle-guarded).
- [x] **Menu bar quick action** „Clean dev junk" (popover → Cleanup dev sken k review).

## Fáze 7 — Vydání 📦 (rozpracováno)
- [ ] Vlastní branding + ikony (NE od CleanMyMac) — zatím SF Symbol `bird.fill`.
- [ ] Developer ID podpis + notarizace + stapling — postup v `docs/RELEASE.md`.
- [x] App bundle skript (`scripts/build-app.sh` → `dist/Kestrel.app`, ad-hoc podpis, LSUIElement).
- [ ] Sparkle auto-update NEBO GitHub Releases — `AppUpdater.sparkleFeed` už čte `SUFeedURL`.
- [x] LICENSE (MIT), README pro veřejnost s reálným použitím. Zbývají screenshoty.
- [ ] Rozhodnout model: čistě OSS / OSS + placené buildy / donationware.

## Fáze 10 — Plná parita s CleanMyMac 🧩🟰
Cíl: **umět vše, co CleanMyMac**, uspořádané jako jeho sekce. `[x]` hotovo, `[~]` částečně, `[ ]` chybí.
Vše drží invarianty: dry-run default, vault + undo, audit, unknown se nemaže, žádné strašení.

### Smart Care (orchestrace jedním klikem)
- [x] **Smart Care** GUI flow (`SmartCareController` + `SmartCareSection`): jeden „Run" → cleanup scan + protection status + Downloads malware scan → jeden čestný výsledek (health/protection/malware tiles + reclaim karta s Move-to-Vault). Zbývá: Applications updates krok.

### Cleanup
- [x] **System Junk** (uživatelské cache/logy, dev-tool cache).
- [x] **Dev-first úklid** (node_modules, DerivedData, Docker/brew, .venv, target…) — *navíc*.
- [x] **Trash Bins** — `TrashFinder`, `kestrel trash` (přes vault, undoable).
- [ ] Rozšířit „System Junk" o systémové cache, broken login items, XPC cache, apod.

### Protection
- [x] **Malware Finder** — čestný scanner (EICAR + heuristika, quarantined) → [ ] bundling **ClamAV + YARA** + freshclam definice.
- [x] **Privacy Items** — browser cache/history/cookies → [ ] rozšířit (recent items, uložené stavy, chat/app logy).
- [x] On-access sken (FSEvents).
- [x] **Application Permissions** — GUI modul `PermissionsSection` nad `TCCReader` (kamera/mikrofon/Full Disk Access/…), read-only, seskupené podle appky s ikonami.

### Performance
- [x] **Maintenance Tasks** — advisory katalog (DNS flush, Spotlight/LaunchServices rebuild, purge, fontcache).
- [x] **Login Items** — výpis `LaunchAgentAuditor` + `kestrel login-items` + **GUI karta v Tools** (orphan badge, reveal).
- [x] **Background Items** — výpis všech agentů/daemonů (`kestrel login-items` / `background-items`).
- [x] **Free up RAM** — `MemoryReliever` (`purge`), tlačítko v Energy Memory kartě (opt-in, non-destructive).
- [x] **Power & Wake auditor** — kdo brání spánku — *navíc*.

### Applications
- [x] **Uninstaller** (bundle + leftovers) — CLI + **GUI modul** (`ApplicationsSection`: ikony, velikosti, uninstall/reset přes vault, search).
- [x] **App Leftovers** (`OrphanFinder`).
- [x] **App Updater** — Homebrew casks outdated **v GUI** (advisory karta s copy `brew upgrade`); Sparkle feedy zbývají.
- [x] **Reset App** — `AppUninstaller.resetPlan`, `kestrel reset` + GUI tlačítko (vymaže data, appku nechá).

### My Clutter
- [x] **Duplicate Finder** (size→partial→full hash).
- [x] **Large & Old Files** (konfig. prahy).
- [x] **Screenshots / Old installers** (`ClutterFinder`) — *navíc oproti CMM granularitě*.
- [x] **Similar Images** — `SimilarImageFinder` (perceptuální aHash), `kestrel photos`.
- [x] **Downloads** — `ClutterFinder.oldDownloads`, `kestrel downloads`.
- [x] **Mail Attachments** — `ClutterFinder.mailAttachments`, `kestrel mail`.

### Space Lens
- [x] `DiskMap` + CLI `map` + **interaktivní treemap v GUI** (`Treemap`, klikací drill-down).

### Cloud Cleanup
- [ ] **iCloud Drive / Dropbox / Google Drive** — offload lokálních kopií (evict, ne smazání).

### My Tools (toolbox)
- [ ] **Toolbox grid GUI** se všemi nástroji (karty + „Scan"), jako CleanMyMac „My Tools" — každý nástroj = existující Core funkce.

### My Activity
- [x] `ActivityReporter` (úspory z audit logu) → [ ] **GUI ledger** (co, kdy, kolik, undo historie).

## Fáze 11 — Design „Precision" 1:1 🎨 (dle návrhu artifactu)
Naportovat schválený návrh (redesign v2) do nativního SwiftUI, komponentu po komponentě.
- [x] Design tokens: paleta „Precision" (grafit + teal accent + sémantika) nasazená.
- [x] Grafitové grunty, hairline (`Hairline`), sklo, prémiové stíny, hloubka (`Card` elevated + tint) napříč app.
- [x] **Hero** health gauge (`HeroGauge`, conic gradient + glow) + verdikt + CTA („Free up space") + „Run Smart Care".
- [x] **Radiální mini-gauge** v dlaždicích (`RadialMetricTile`); síťová sparkline na dashboardu, CPU sparkline v detailu.
- [x] **Seskupený sidebar** (Monitor / Maintain / Intelligence) s ikonami, accent glow lištou aktivního stavu.
- [x] **AI insight strip** (dashboard, on-demand, metadata-only), **Storage forecast** karta (`ForecastCard`), **Security status** karta (`ProtectionCard`).
- [~] **My Tools** toolbox grid — hotové karty finderů (`PlanToolCard`); zbývá dotáhnout ostatní nástroje.
- [x] **Command palette (⌘K)** — spusť/najdi jakoukoli akci (tintované ikony, highlight, hint patička).
- [~] Redesign **menubar popoveru** — už plně custom (chip cluster, action/speed karty); drobný sjednocující pass zbývá.
- [x] Sjednocené komponenty: **žádný defaultní Apple control** — vlastní progress (`KestrelProgress`), spinner (`KestrelSpinner`), switch (`KestrelToggle`), confirm modal (`ConfirmModal`), select (`KestrelSelect`), tlačítka, karty, gauge; light/dark přes sémantickou paletu.

## Fáze 12 — Extra funkce (co CleanMyMac NEMÁ) 🚀
Diferenciátory — většina už hotová, tady jako přehled + zbytek.
- [x] Dev-first úklid (chápe repozitáře), [x] Vault + Undo, [x] Secrets scanner, [x] čestný AV (nestraší),
      [x] Energy per-app + quit + live time-left, [x] Zero telemetry, [x] plné CLI (skriptovatelné, CI/cron),
      [x] AI asistent + „druhý názor", [x] Storage forecast, [x] Rules engine + launchd, [x] Shredder.
- [x] **Čeština / lokalizace** — vlastní vrstva (`Localization.swift`, `L()`, ~350 hesel, duplicate-safe),
      přepínač v Settings (Systém/Čeština/English), přepíná se naživo; přeloženo celé UI.
- [x] **Energy: jméno + ikona aplikace** (resolver přes NSRunningApplication/proc_pidpath) + **AI „proč to žere"** per proces.
- [x] **Security: Quarantine viewer** (`QuarantineReader.scan`, co přišlo z internetu + agent).
- [x] **Cleanup: výběr kategorií** (zaškrtávátka), **Applications: nepoužívané appky + řazení + celková velikost**.
- [x] **Automation modul** (GUI nad Rules engine + `RulesScheduler` LaunchAgent: pravidla, náhled, run-now, plán).
- [x] **First-run onboarding**, **⌘1–9** zkratky na sekce, **klikací dlaždice** dashboardu → detail.
- [x] Command palette (⌘K, klávesová navigace), [x] Lokální notifikace, [x] Free up RAM, [x] App Permissions (TCC),
      [x] Login Items viewer, [x] Drag&drop sken složky, [x] **Bandwidth monitor per-app** (`BandwidthMonitor`, nettop),
      [x] **Batch uninstall** (multi-select + kombinovaný review), [x] „Explain this" (security nálezy),
      [x] **Weekly digest (GUI)** — copyable text summary v Activity,
      [~] **Apple Shortcuts** — App Intents hotové (`KestrelShortcuts`: Mac Health / Free Space / Dev Junk,
      read-only/dry-run); plná registrace do Shortcuts vyžaduje Xcode „Extract App Intents Metadata" (Fáze 7).

## Fáze 13 — Hloubková code review & audit 🔍 (průběžně)
Cíl: nekompromisní audit celého projektu (frontend `KestrelApp` / doména `KestrelCore` /
„DB" manifesty+audit log+SQLite / cloud = žádný, offline-first) — modul po modulu, funkce
po funkci. Výstup je `docs/AUDIT.md` ve fixním formátu:
**### [ZÁVAŽNOST] Název** → *Lokace* · *Popis* · *Riziko* · *Návrh řešení (s kódem)*.
Závažnosti od nejnižší: **[NÍZKÁ/KOSMETICKÁ] → [STŘEDNÍ/REFAKTOR] → [VYSOKÁ/BUDOUCÍ BUG] → [KRITICKÁ]**,
plus závěrečné **Architektonické zhodnocení**. Každý nález řešit v kontextu invariantů z `CLAUDE.md`.
- [x] **1. kolo auditu** → `docs/AUDIT.md` (nálezy seřazené dle závažnosti).
- [x] **Kritické/Vysoké opraveny v 1. kole:** vault restore data-loss (+ data-safety test),
      tiché move failures, MenuBar popover Back dismiss, re-sken aplikací.
- [x] **VYSOKÁ — GUI PATH bug:** zabalená appka nenašla `brew`/`clamav` (minimální PATH) →
      updaty tiše nefunkční; `ProcessRunner` teď předřazuje tool adresáře.
- [x] **Střední/refaktor (2. kolo):** Swift 6 concurrency vyřešeno (0 warningů), líné
      načítání app ikon, notifikační race, `MemoryReliever` ověřuje existenci `purge`,
      vystavování chyb u Cleanup scanu (místo tichého `try?`).
- [x] **Kosmetika:** aliasy palety zdokumentovány, sdílený `failureSuffix` helper;
      `id: \.offset` posouzeno (seznamy se nahrazují najednou → bezpečné, ponecháno).
- [x] **3. kolo:** proveden review zbylých modulů (DiskMap, RuleScanner, DuplicateFinder,
      SafetyGuard, DevArtifactClassifier, EnergyLog, GeminiClient) — jádro **solidní, bez
      dalších reálných bugů**. Jediný drobný nález: `AppUpdater` zobrazoval revizní hash za
      čárkou → opraveno (`cleanVersion`) + test. Coverage 213 testů.

---

## Návrh prvního sprintu (co říct Claudovi)
> „Rozjeď Fázi 0: založ SPM workspace, naimplementuj VaultService a AuditLog
> s testy na temp adresářích a přidej CLI příkaz `kestrel vault list/undo`.
> Dodržuj invarianty z CLAUDE.md."
