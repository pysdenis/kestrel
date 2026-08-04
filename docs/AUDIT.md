# Kestrel — hloubková code review & audit

> Audit nativní macOS aplikace (SwiftUI + `KestrelCore`, Swift Package Manager).
> Mapování na webový/cloud model: **frontend** = `Sources/KestrelApp` (SwiftUI),
> **backend/doména** = `Sources/KestrelCore`, **„databáze"** = JSON manifesty vaultu +
> audit log (JSON-lines) + read-only SQLite (`TCC.db`), **cloud** = záměrně žádný
> (offline-first, zero telemetry — viz invarianty v `CLAUDE.md`).
>
> Nálezy jsou řazeny od nejméně po nejvíce závažné. Položky označené **✅ OPRAVENO**
> byly vyřešeny v rámci této revizní session (viz git historie).

---

## [NÍZKÁ / KOSMETICKÁ]

### [NÍZKÁ] Redundantní aliasy v paletě
- **Lokace:** `Sources/KestrelApp/Palette.swift`
- **Popis:** `teal = accent`, `violet = accent2`, `blue = accent2` jsou aliasy téže barvy. Dva různé názvy pro jednu barvu svádějí k domněnce, že jde o odlišné tokeny.
- **Riziko:** Při budoucí změně palety někdo přebarví `accent2`, ale zapomene, že `violet` i `blue` jsou totéž → nekonzistence.
- **Návrh řešení:** Ponechat jen sémantické názvy (`accent`, `accent2`, `good/warn/crit`) a aliasy odstranit, nebo je jasně zdokumentovat jako „intentional alias".

### [NÍZKÁ] `id: \.offset` napříč `ForEach`
- **Lokace:** `Sections.swift`, `MainWindow.swift`, `Applications.swift` (mnoho míst)
- **Popis:** Kolekce se iterují přes `Array(x.enumerated())` s `id: \.offset`. Index jako identita znamená, že SwiftUI neumí správně diffovat při reorderingu/odebrání.
- **Riziko:** Kosmetické glitche animací u seznamů, které se mění za běhu (např. energy list). U statických seznamů neškodí.
- **Návrh řešení:** Tam, kde má prvek stabilní klíč (cesta, pid, id), použít ho: `ForEach(items, id: \.pid)`.

### [NÍZKÁ] ✅ OPRAVENO — Duplikovaná formátovací logika hlášek
- **Lokace:** `ScanControllers.swift`, `Applications.swift`
- **Popis:** Skládání „N couldn't be moved …" bylo 4× zkopírované.
- **Riziko:** Rozjela by se konzistence textace při budoucí úpravě.
- **Návrh řešení (implementováno):** Sdílený `ExecutionResult.failureSuffix` na jednom místě.

---

## [STŘEDNÍ / REFAKTOR]

### [STŘEDNÍ] `try?` spolyká chyby v controllerech
- **Lokace:** `Sources/KestrelApp/ScanControllers.swift` (18×), `Applications.swift`
- **Popis:** Skenování/`listSessions`/plánování používá `try?`, takže reálná chyba (I/O, oprávnění) zmizí a UI zobrazí prázdný výsledek jako „nic nenalezeno". Restore a `ExecutionResult.failures` už čestně reportují (opraveno), ostatní cesty ne.
- **Riziko:** Uživatel dostane falešné „čisto/nic tu není", zatímco reálně chybí oprávnění nebo selhalo čtení → ztráta důvěry, těžké ladění.
- **Návrh řešení:** Zavést typed error kanál na controllerech (`@Published var lastError: String?`) a místo `try?` chytit a vystavit důvod, min. u scan cest.
```swift
do { let r = try ScanCoordinator().scan(root: root) { … }; … }
catch { await MainActor.run { self.lastError = "Scan failed: \(error.localizedDescription)" } }
```

### [STŘEDNÍ] ✅ OPRAVENO — Swift 6 concurrency warningy (`self` capture)
- **Lokace:** `ScanControllers.swift`, `Applications.swift`, `Permissions.swift`, `DashboardModel.swift`
- **Popis:** Kompilátor hlásil „reference to captured var 'self' in concurrently-executing code; this is an error in the Swift 6 language mode" u každého `await MainActor.run { self?… }` uvnitř detached tasku.
- **Riziko:** Po přechodu na Swift 6 language mode by se z warningů staly chyby → nekompiluje.
- **Návrh řešení (implementováno):** Každý `await MainActor.run` uzavírá `self` čerstvě (`{ [weak self] in … }`) místo reference na weak var z vnějšího closure. Build je nyní na tuto třídu **bez warningů (0)**, bez změny chování.

### [STŘEDNÍ] ✅ OPRAVENO — `MemoryReliever` nehlásil reálný výsledek `purge`
- **Lokace:** `Sources/KestrelCore/Stats/MemoryReliever.swift`
- **Popis:** `freeInactiveMemory()` vracelo `true`, i když `purge` neexistuje.
- **Riziko:** UI napsalo „hotovo", aniž se cokoli stalo (porušení invariantu čestnosti #6).
- **Návrh řešení (implementováno):** Ověření existence binárky (`/usr/sbin/purge`) před spuštěním; úspěch se hlásí jen když tool existuje a doběhl.

### [STŘEDNÍ] ✅ OPRAVENO — Ikony aplikací se načítaly na main threadu
- **Lokace:** `Sources/KestrelApp/Applications.swift`
- **Popis:** `NSWorkspace.shared.icon(forFile:)` v cyklu přes všechny appky běžel na `@MainActor` naráz.
- **Riziko:** Při stovkách aplikací krátký lag/jank při otevření modulu.
- **Návrh řešení (implementováno):** Ikona se načítá per-`AppCard` v `onAppear`, takže `LazyVGrid` řeší jen viditelné buňky.

### [STŘEDNÍ] ✅ OPRAVENO — Race při autorizaci notifikací
- **Lokace:** `Sources/KestrelApp/Notifier.swift`
- **Popis:** `requestAuthorization` nastavoval `authorized` asynchronně; první `notify` volané dřív se zahodilo.
- **Riziko:** První upozornění na málo místa mohlo být tiše ztraceno.
- **Návrh řešení (implementováno):** `notify` čte živý `getNotificationSettings` před posláním, nezávisle na async flagu.

---

## [VYSOKÁ / BUDOUCÍ BUG]

### [VYSOKÁ] ✅ OPRAVENO — Restore z vaultu ztrácel data při částečném undo
- **Lokace:** `Sources/KestrelCore/Vault/VaultService.swift` — `undo(session:)`
- **Popis:** `undo` používal `try?` a **na konci vždy smazal session složku**. Když se část položek neobnovila (cíl obsazen, nebo bundled app bez Full Disk Access nemohla zapsat do `~/.Trash`/`~/Library`), jejich kopie ve vaultu se nenávratně smazaly a UI hlásilo prázdné „Restored 0" → uživatel viděl „restore nic nedělá".
- **Riziko:** Nevratná ztráta dat + falešný dojem nefunkčnosti — kritické pro nástroj na obnovu.
- **Návrh řešení (implementováno):** `undo` vrací `UndoOutcome (restored/skippedExisting/failed)`, session maže **jen** když je vault prázdný, jinak přepíše manifest se zbytkem (nic se neztratí). CLI i GUI hlásí, co a proč selhalo, a navádí na Full Disk Access.

### [VYSOKÁ] ✅ OPRAVENO — Selhání přesunu se tiše zahazovala
- **Lokace:** `CleanupExecutor` (Core sbírá `failures`) vs. GUI (`Cleanup/Applications/Tools/SmartCare`)
- **Popis:** GUI ignorovalo `ExecutionResult.failures`, takže položka, kterou nešlo přesunout (např. app v `/Applications` vyžadující admin), zmizela z hlášení.
- **Riziko:** Uživatel si myslí, že se vše uklidilo, přitom část zůstala.
- **Návrh řešení (implementováno):** Všechna místa reportují počet nepřesunutých položek.

### [VYSOKÁ] ✅ OPRAVENO — MenuBar popover se zavíral při „Back"
- **Lokace:** `Sources/KestrelApp/DashboardView.swift` — `MenuBarView`
- **Popis:** V `.window`-style `MenuBarExtra` synchronní změna navigačního `@State` uvnitř kliku způsobila, že transientní okno vyhodnotilo přestavbu hierarchie jako dismiss → Back zavřel celý popover.
- **Riziko:** Nefunkční navigace v hlavní ploše menubar appky.
- **Návrh řešení (implementováno):** Odložení změny stavu na další runloop tick (`DispatchQueue.main.async`).

### [VYSOKÁ] ✅ OPRAVENO — Re-sken všech aplikací při každém příchodu
- **Lokace:** `Applications.swift` — `AppsController.load()`
- **Popis:** Chyběl `loaded` guard, takže každý návrat do modulu přeměřil velikost všech bundlů znovu.
- **Riziko:** Zbytečná zátěž disku/CPU při navigaci.
- **Návrh řešení (implementováno):** `loaded` guard + `load(force:)` po uninstallu.

### [VYSOKÁ] ✅ OPRAVENO — Zabalená GUI appka nenašla externí nástroje (PATH)
- **Lokace:** `Sources/KestrelCore/External/CommandRunner.swift` — `ProcessRunner.run`
- **Popis:** GUI appka spuštěná z Finderu/`open` dědí minimální PATH (`/usr/bin:/bin:/usr/sbin:/sbin`) bez Homebrew. `/usr/bin/env brew …` proto `brew` nenašlo → „Updates available" karta byla vždy prázdná, ClamAV/docker adaptéry taky tiše nefungovaly. Z CLI to fungovalo jen díky shellovému PATH.
- **Riziko:** Celá třída advisory funkcí (updaty, AV, docker) v GUI tiše nefunkční → uživatel netuší proč („aktualizace nefungují").
- **Návrh řešení (implementováno):** `ProcessRunner` předřazuje běžné tool adresáře (`/opt/homebrew/bin`, `/usr/local/bin`, …) do PATH, takže nástroje se najdou nezávisle na způsobu spuštění. Ověřeno v minimálním prostředí.

### [VYSOKÁ] ✅ OPRAVENO (komunikací) — TCCReader vidí jen uživatelskou TCC databázi
- **Lokace:** `Sources/KestrelCore/Privacy/TCCReader.swift`, `Sources/KestrelApp/Permissions.swift`
- **Popis:** Čte `~/Library/Application Support/com.apple.TCC/TCC.db`. Některá klíčová oprávnění (Full Disk Access, Accessibility, Screen Recording) žijí v **systémové** DB (`/Library/...`), která vyžaduje root.
- **Riziko:** Permissions modul může pod-reportovat právě ta nejcitlivější oprávnění → uživatel by mohl být uveden v omyl (naráží na invariant čestnosti #6).
- **Návrh řešení (implementováno):** UI teď explicitně uvádí, že jde o **per-user** grants a že systémová (FDA/Accessibility) žijí v root-only DB a nemusí se zobrazit → spravovat v System Settings. (Čtení systémové DB by vyžadovalo root, mimo scope.)

---

## [KRITICKÁ]

### [KRITICKÁ] ✅ OPRAVENO — Ztráta dat ve vault restore
- Viz výše (nejzávažnější reálný nález této revize; opraveno + přidán data-safety test).
- **Poznámka k bezpečnosti:** Mimo tento nález audit **nenašel** hardcoded klíče (AI klíč dodává uživatel souborem `~/.kestrel/gemini.key`, mimo repo), žádnou telemetrii, žádné síťové volání kromě opt-in (Gemini metadata / Cloudflare speed test na akci), a žádnou injekci — SQLite dotazy jsou konstantní a read-only nad lokální DB, bez vstupu uživatele do SQL. `rm` se nikde nepoužívá; vše jde přes vault.

---

## Architektonické zhodnocení

- **Bezpečnostní jádro je silné a je to hlavní devíza projektu.** Vault → undo → audit → dry-run default tvoří konzistentní model, který nález výše (jediná díra v něm) po opravě uzavírá. Doporučuji držet každou novou destruktivní cestu za `SafetyGuard` + vaultem s testem na dry-run.
- **Čisté vrstvení** `KestrelCore` (bez UI) ← `KestrelApp`/`kestrel-cli` je dobře udržovatelné a testovatelné (207 dependency-free testů). Business logika je oddělená od SwiftUI.
- **Offline-first je bezpečnostní výhoda, ne omezení:** absence cloudu/účtů/telemetrie eliminuje celou třídu rizik (únik dat, přístupové tokeny, GDPR). Jediné egress body (Gemini, speed test) jsou opt-in a posílají jen metadata.
- **Hlavní technický dluh k dořešení:** (1) přechod na Swift 6 concurrency (dnes warningy), (2) centralizace vystavování chyb místo `try?`, (3) zrušitelnost dlouhých scanů, (4) čtení/označení systémové TCC DB.
- **Doporučení pro distribuci (deployment):** Developer ID podpis + notarizace + stapling (dnes jen ad-hoc podpis, viz `docs/RELEASE.md`), Full Disk Access onboarding (mnoho funkcí ho vyžaduje — Trash, Mail, TCC, restore do chráněných cest), a sandbox rozvaha (uninstaller a TCC čtení jsou s app sandboxem v napětí — pravděpodobně distribuovat mimo Mac App Store).
- **Celkový stav:** zdravý, dobře strukturovaný projekt s jasnými invarianty; po opravách v této revizi jsou známé kritické/vysoké nálezy uzavřené, zbývající jsou střední/kosmetické a plánovatelné.
