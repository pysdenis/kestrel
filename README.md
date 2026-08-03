# Kestrel 🦅

> Lehká, čestná a rychlá utilita pro údržbu macOS. Menubar dashboard, chytré
> čištění místa, vlastní antivirus a nástroje, které CleanMyMac nemá.
>
> **Kestrel** je pracovní název — klidně přejmenuj (viz `docs/LEGAL.md`, kap. Naming).

Nativní Swift/SwiftUI. Žádný Electron, žádné „strašení", žádné mazání naslepo.
Vše, co Kestrel udělá, je **předem vidět, potvrditelné a vratné**.

---

## Proč tohle vzniká

CleanMyMac je z 90 % hezký obal nad věcmi, které macOS umí sám. Zbylých 10 %
je marketing (fake „malware found", „optimalizace RAM"). Kestrel chce:

1. **Být čestný** — žádné vymyšlené hrozby, žádná placebo tlačítka.
2. **Být bezpečný** — dry-run defaultně, karanténa místo `rm`, plný audit log.
3. **Být lepší pro vývojáře** — Docker, node_modules, DerivedData, .venv,
   build artefakty. Tohle CleanMyMac ignoruje a přitom to bere nejvíc místa.
4. **Být lehký** — jedna nativní menubar appka, ne 500 MB balík.

---

## Základní filozofie (nepřekročitelná pravidla)

| Princip | Co to znamená v kódu |
|---|---|
| **Dry-run first** | Každá destruktivní operace má `--dry-run` a je to default. |
| **Karanténa, ne smazání** | Soubory jdou do `~/.kestrel/vault/` s N-denní retencí, teprve pak `rm`. |
| **Nic naslepo** | Vždy: sken → seznam s velikostmi → potvrzení uživatelem. |
| **Audit log** | Každá akce zapsaná do `~/.kestrel/audit.log` (co, kdy, kolik, odkud kam). |
| **Žádné strašení** | Antivirus reportuje jen to, co reálně našel, s odkazem na důkaz. |
| **Reversibilita** | „Undo" na poslední úklid, dokud je ve vaultu. |

---

## Funkce

### 🧹 Chytré čištění místa
- **Uživatelské cache/logy** — `~/Library/Caches`, `~/Library/Logs`, `/private/var/folders`.
- **Vývojářský junk (killer feature)** — Xcode DerivedData & simulátory, `node_modules`,
  `.venv`, `target/`, `dist/`, `build/`, Gradle/Maven/CocoaPods cache. Skenuje repozitáře
  a nabídne smazání znovu-generovatelných věcí.
- **Docker cleanup** — dangling images, stopped containers, nepoužité volumes/networks
  (`docker system df` → přehled, `prune` s náhledem).
- **Duplicitní soubory** — velikost → částečný hash → plný hash (rychlé, přesné).
- **Velké & staré soubory** — konfigurovatelné prahy, náhled, řazení.
- **Odinstalace appek i se zbytky** — bundle + Application Support + Preferences +
  Caches + LaunchAgents + saved state.
- **Koš, Downloads triage, prázdné složky, .DS_Store, staré iOS zálohy.**

### 📊 Přehled místa (lepší než „koláč" v Nastavení)
- **Interaktivní treemap / sunburst** celého disku (jako `ncdu`, ale hezky).
- **Storage over time** — Kestrel si ukládá denní snímky využití a kreslí trend.
- **„Co mi sežralo místo"** — diff proti minulému týdnu: které složky narostly.
- **Předpověď zaplnění** — lineární/spline extrapolace „za ~X dní ti dojde místo".
- **Per-app skutečná stopa** — ne jen velikost bundle, ale i všechny jeho cache/support.

### 🛡️ Vlastní antivirus (čestný)
- **ClamAV engine** (open-source) + auto-update definic.
- **YARA pravidla** pro známé Mac malware/adware rodiny.
- **Heuristika**: nepodepsané binárky se síťovou aktivitou, spouštěné z Downloads,
  přepsané `PATH`/dylib injection, podezřelé LaunchAgents/LaunchDaemons.
- **Napojení na systém**: čte stav **XProtect / Gatekeeper**, hlásí neshody
  (nezastupuje je — spolupracuje s nimi).
- **Quarantine viewer** — co macOS označil `com.apple.quarantine`.
- **On-access i on-demand** sken (on-access přes FSEvents na Downloads/Desktop).
- **Nulové strašení** — když je čisto, řekne „čisto" a proč tomu věřit.

### 🖥️ Menubar dashboard (ten z inspiračního screenshotu, ale vlastní)
- Mac Health skóre (vlastní heuristika, transparentně rozklikací).
- Disk (volné místo) · Memory pressure · Battery + zdraví · CPU load.
- Wi-Fi SSID + live up/down throughput · Speed test.
- Externí disky (mount/eject).
- „Dnešní doporučení" — jen reálná, ne generovaná ze strachu.

---

### 🧩 Pokrytí celého CleanMyMac okna
Sidebar CleanMyMacu je namapovaný 1:1 v `docs/FEATURES.md`:
Smart Care · Cleanup · Protection · Performance · Applications (vč. **App Updater**) ·
My Clutter · Space Lens · **Cloud Cleanup** · My Tools (Toolbox) · My Activity.
Plus **SmartScan** (jednotlačítková orchestrace) a čestný **System Tune-up / Security Check**.

## Funkce navíc, které CleanMyMac NEMÁ 🚀

1. **Dev-mode úklid** — chápe repozitáře; smaže jen znovu-generovatelné artefakty,
   nikdy zdrojáky. (Docker/node/Xcode/Python/Rust/Java.)
2. **Recycle Vault + Undo** — nic se nemaže hned; N dní karanténa, jedno kliknutí zpět.
3. **Storage time-machine & předpověď** — trendy a „dojde ti místo za X dní".
4. **Power & Wake auditor** — kdo drží `pmset` assertions a brání spánku, kdo budí Mac
   z lišty (řeší reálný problém „notebook se v tašce nevyspí a přehřeje se").
5. **Login items & LaunchAgent auditor** — co ti startuje při bootu, s dopadem a
   možností vypnout; ukáže i „osiřelé" agenty po odinstalovaných appkách.
6. **Rules engine / automatizace** — např. „Downloads starší 30 dní → vault",
   „po každém buildu vyčisti DerivedData", spouštěné přes `launchd`.
7. **CLI + skriptovatelnost** — celé jádro použitelné z terminálu i v CI/cronu.
8. **Plně offline & bez telemetrie** — žádná data ven, žádný účet. Prodejní argument.
9. **Bandwidth monitor per-app** — kdo žere data na pozadí.
10. **„Explain this file"** — u nalezeného junku vysvětlí, co to je a proč je bezpečné to smazat.
11. **APFS local snapshots & Time Machine local cleanup** — skryté „purgeable" místo (často desítky GB).
12. **Secrets/credential scanner** — najde v projektech omylem uložené API klíče a hesla.
13. **Apple Shortcuts integrace** — akce jako Shortcuts pro vlastní automatizace.
14. **Homebrew maintenance** — `brew cleanup`, staré verze, orphaned deps.
15. **Duplicitní & podobné fotky** (perceptual hash) + úklid Screenshotů.
16. **Config profile / kernel & system extensions audit** — bezpečnostní přehled.

> Plný katalog všech funkcí (A: pokrytí CleanMyMacu 1:1, B: extra, C: killer diferenciátory)
> je v **`docs/FEATURES.md`**.

---

## Architektura (stručně)

```
kestrel/
├─ KestrelCore/      # Swift package — veškerá logika, bez UI (scan, clean, av, stats)
├─ kestrel-cli/      # CLI nad Core (dry-run default, skriptovatelné)
├─ KestrelApp/       # SwiftUI menubar app (NSStatusItem + NSPopover) nad Core
├─ Resources/        # ClamAV/YARA definice, ikony (VLASTNÍ, ne CleanMyMac)
└─ docs/
```

Jádro (`KestrelCore`) nezná UI. CLI i GUI jsou jen tenké slupky nad ním →
testovatelné, znovupoužitelné, snadné na code review. Detaily v `docs/ARCHITECTURE.md`.

---

## Instalace a použití (CLI)

Vyžaduje Swift 5.9+ (Command Line Tools stačí, Xcode netřeba).

```bash
swift build                        # sestaví KestrelCore + kestrel (CLI) + KestrelApp (GUI)
swift run kestrel-tests            # spustí testovou sadu (dependency-free runner)
swift run kestrel help             # přehled příkazů
```

Vše je **dry-run defaultně** — `clean`/`uninstall`/`orphans`/`installers` nic nesmažou
bez `--apply`, a i pak jdou soubory do `~/.kestrel/vault/` (vratné přes `vault undo`).

```bash
kestrel scan ~/Developer                     # co lze uklidit (+ opt-in review sekce)
kestrel clean ~/Developer --category dev      # náhled jen dev-artefaktů
kestrel clean ~/Developer --category dev --apply
kestrel uninstall Slack                        # appka + zbytky → vault
kestrel orphans                                # data po odinstalovaných appkách
kestrel map ~/Library --depth 2                # treemap v terminálu
kestrel snapshot; kestrel trend; kestrel diff  # vývoj místa v čase
kestrel stats                                  # Mac Health + disk/mem/cpu/battery/net
kestrel av scan ~/Downloads                    # čestný sken (EICAR + heuristika)
kestrel av status                              # Gatekeeper + XProtect
kestrel secrets ~/myproject                    # uniklé API klíče/tokeny (redigované)
kestrel smartscan                              # jednotlačítkový přehled
kestrel docker; kestrel brew                   # reclaimable místo (advisory)
kestrel power; kestrel localsnapshots          # co brání spánku / lokální snapshoty
kestrel activity                               # kolik místa Kestrel reálně uvolnil
```

### Menubar app
```bash
./scripts/build-app.sh             # → dist/Kestrel.app (ad-hoc podpis, běží lokálně)
open dist/Kestrel.app
```

## Stav / Roadmap (fáze)

- **Fáze 0** ✅ — `KestrelCore`, audit log, vault, dry-run infra.
- **Fáze 1** ✅ — čisticí jádro + CLI (cache/logy, dev-junk s project-markery, duplicity
  size→partial→full hash, velké/staré, app uninstaller).
- **Fáze 2** ✅ — přehled místa (treemap, denní snímky, trend, předpověď, diff).
- **Fáze 3** ✅ — StatsCollector (veřejná API) + Mac Health + SwiftUI menubar app.
- **Fáze 4** 🟡 — čestný on-demand antivirus (EICAR + heuristika, Gatekeeper/XProtect,
  quarantine, osiřelí agenti). Zbývá: bundling ClamAV+YARA, on-access watcher.
- **Fáze 5** 🟡 — SmartScan, maintenance, orphaned data, privacy cleaner, activity.
  Zbývá: Cloud Cleanup.
- **Fáze 6** 🟡 — secrets scanner, power auditor, local snapshots, installers/screenshots,
  shredder. Zbývá: rules engine, bandwidth monitor, perceptual-hash fotky.
- **Fáze 7** 🟡 — MIT LICENSE, app bundle skript, release/notarizace postup
  (`docs/RELEASE.md`). Zbývá: Developer ID podpis + notarizace, vlastní ikona.

Podrobné checklisty (co hotovo / co zbývá) viz `docs/ROADMAP.md`.
154 testů zelených (`swift run kestrel-tests`).

> Advisory funkce (Docker/brew/ClamAV prune, maintenance) Kestrel **sám neprovádí** —
> ukáže reclaimable místo a přesný příkaz. Jejich úložiště nejde do vaultu, tak by to
> porušilo „karanténa místo rm". Skutečné provedení = explicitní krok uživatele.

---

## Vývoj ve VSCode (bez Xcode)

Celé Core + CLI (Fáze 0–2) se vyvíjí **plně ve VSCode** — Xcode netřeba.
Potřebné rozšíření: `swiftlang.swift-vscode` + `llvm-vs-code-extensions.lldb-dap`
(obojí už nainstalováno). `.vscode/` obsahuje připravené tasks a launch konfigurace:

- **Build:** `Cmd+Shift+B` (task „swift: build")
- **Testy:** paleta → „Run Test Task" nebo `swift run kestrel-tests`
- **Debug:** panel Run and Debug → „Run tests" / „CLI: scan ~/Downloads" (breakpointy fungují)
- Autocomplete, diagnostika a „go to definition" jede přes `sourcekit-lsp`.

Terminálem kdykoli: `swift build`, `swift run kestrel-tests`, `swift run kestrel scan <cesta>`.

> **Xcode budeš potřebovat až u GUI (Fáze 3)** — na SwiftUI live previews a hlavně na
> finální **code signing + notarizaci** pro distribuci. Psát a spouštět appku ale půjde
> dál i z VSCode; Xcode je pak spíš „build/sign nástroj na pozadí" než místo, kde žiješ.

## Rychlý start pro vývoj (s Claudem)

1. Přečti `CLAUDE.md` — pravidla, konvence, bezpečnostní invariants.
2. Zvol fázi z `docs/ROADMAP.md`.
3. Začni `KestrelCore` + testy, teprve pak CLI, teprve pak GUI.
4. **Nikdy** neobcházej dry-run/vault invariants (viz `CLAUDE.md`).

## Právní / distribuce

- Vlastní kód, vlastní jméno, vlastní ikony — funkce se nechrání, konkrétní výraz ano.
- Open-source (MIT/GPL) i placené buildy jsou OK. Detaily a rizika v `docs/LEGAL.md`.
- Distribuce mimo App Store → Apple Developer účet ($99/rok) + notarizace.

---

*Stav: 🛠️ Fáze 0–7 z podstatné části hotové — funkční CLI + kompilovatelná menubar app,
154 testů zelených. Zbývá dotáhnout advisory→reálné provedení, ClamAV/YARA bundling,
on-access sken, Cloud Cleanup a Developer ID podpis/notarizaci.*
