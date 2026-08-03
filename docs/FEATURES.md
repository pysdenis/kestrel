# Feature katalog

Kompletní seznam funkcí. Rozdělený na (A) pokrytí CleanMyMac sidebaru 1:1,
(B) extra funkce navíc, (C) „killer" diferenciátory, které CleanMyMac nemá.

Legenda pokrytí: ✅ v plánu · ➕ přidáno v této iteraci · 🆕 nad rámec CleanMyMacu

---

## A) Mapování CleanMyMac sidebaru → Kestrel

| CleanMyMac sekce | Co obsahuje | Kestrel ekvivalent | Stav |
|---|---|---|---|
| **Smart Care** (Quick Scan, System Tune-up, Security Check) | jednotlačítková orchestrace | `SmartScan` — spustí clean+stats+AV pipeline, ukáže souhrn, potvrzení | ➕ |
| **Cleanup** | cache, logy, junk, koš | Fáze 1 – čisticí jádro | ✅ |
| **Protection** | antivirus, ochrana soukromí | Fáze 4 – AV + Privacy cleaner | ✅ |
| **Performance** | tune-up, maintenance, login items, RAM | `MaintenanceService` + Login/Agent auditor | ➕ |
| **Applications** | odinstalace, updater, resety | Uninstaller ✅ + **App Updater** ➕ + Reset ➕ |
| **My Clutter** | duplicity, podobné, velké/staré | Fáze 1 – duplicity/velké + **podobné fotky** | ✅➕ |
| **Space Lens** | vizuální mapa disku | Fáze 2 – DiskMap treemap/sunburst | ✅ |
| **Cloud Cleanup** | čištění iCloud/cloud úložišť | **CloudCleanup** (iCloud Drive, Dropbox, GDrive) | ➕ |
| **My Tools** | sada malých utilit | **Toolbox** (viz níže) | ➕ |
| **My Activity** | historie akcí a úspor | `ActivityView` nad AuditLog + statistiky úspor | ➕ |

### Doplněné sekce (detaily)

**Smart Care / SmartScan**
- Jedním tlačítkem: rychlý sken cache + duplicit + AV quick scan + kontrola updatů +
  stav ochrany. Výstup = jeden přehledný souhrn s odhadem úspory a bezpečným „Apply".
- „System Tune-up" = náš `MaintenanceService` (viz Performance), ne placebo.
- „Security Check" = AV quick + XProtect/Gatekeeper/FileVault/Firewall stav + přehled
  rizikových LaunchAgents.

**Performance / MaintenanceService** (čestné tune-upy, žádné placebo RAM triky)
- Spuštění systémových `periodic` maintenance skriptů.
- Flush DNS cache, rebuild Spotlight index (`mdutil`), rebuild Launch Services DB
  (opravuje „Otevřít v" duplicity), reset font cache.
- Vyčištění swapu/purgeable po potvrzení (bez slibů o „zrychlení").
- Přehled Login items + LaunchAgents/Daemons s dopadem a vypnutím.

**Applications**
- **App Updater** — porovná nainstalované appky s nejnovějšími verzemi
  (Homebrew casks + Sparkle feedy + volitelně MacUpdater-style katalog). Nabídne update.
- **Uninstaller** — bundle + všechny leftovers (Application Support, Prefs, Caches,
  LaunchAgents, saved state, containers).
- **Reset app** — vrátí appku do „jako po instalaci" (smaže jen její data, ne appku).
- **Orphaned data finder** — data po appkách, které už nejsou nainstalované.

**Cloud Cleanup**
- iCloud Drive / Dropbox / Google Drive: najde velké a duplicitní soubory, staré verze,
  „evicted vs. stažené" (co zbytečně zabírá lokálně vs. je jen v cloudu).
- Umí soubory „offloadovat" (nechat jen v cloudu) místo mazání. Pozor na provider API.

**My Tools / Toolbox** (sbírka malých, ale užitečných nástrojů — viz sekce C)

---

## B) Extra funkce navíc (nad CleanMyMac základ)

| Funkce | Popis | Stav |
|---|---|---|
| **Recycle Vault + Undo** | karanténa místo mazání, N-denní retence, jedno kliknutí zpět | 🆕 |
| **Dev-mode úklid** | node_modules, DerivedData, target/, .venv, dist/, Docker prune | 🆕 |
| **Storage time-machine** | denní snímky využití, trend, předpověď zaplnění | 🆕 |
| **„Co narostlo od minule"** | diff využití proti minulému týdnu | 🆕 |
| **Power & Wake auditor** | kdo brání spánku / budí Mac (pmset assertions, wake reasons) | 🆕 |
| **Privacy cleaner** | historie prohlížečů, cookies, trackery, recent items, clipboard | ➕ |
| **Zero telemetry** | nic neodchází, žádný účet — prodejní i právní plus | 🆕 |
| **CLI + skriptovatelnost** | celé jádro z terminálu, použitelné v cronu/CI | 🆕 |
| **Rules engine** | „when → do" automatizace přes launchd | 🆕 |
| **Bandwidth monitor** | per-app spotřeba dat na pozadí | 🆕 |
| **Battery health dashboard** | cykly, kondice, teplota, připomínka charge-limitu | ➕ |

---

## C) Killer diferenciátory 🆕 (tohle CleanMyMac buď nemá, nebo dělá špatně)

1. **APFS local snapshots & Time Machine local cleanup** — skryté „purgeable" místo,
   které normálně nevidíš. Často desítky GB. Kestrel je zobrazí a bezpečně smaže staré
   lokální snapshoty (`tmutil`). *Tohle je jeden z největších reálných zisků místa.*

2. **Secrets / credential scanner (pro vývojáře)** — projde tvé projekty a najde
   omylem uložené API klíče, tokeny, `.env` s hesly, privátní klíče mimo `~/.ssh`.
   Nemaže — upozorní. Genuinně užitečné pro tebe jako developera.

3. **Apple Shortcuts integrace** — vystaví akce (Free Up, Quick Scan, Purge Vault…)
   jako Shortcuts → uživatel si je zapojí do vlastních automatizací a Focus režimů.

4. **Homebrew maintenance** — `brew cleanup`, staré verze, orphaned deps, cache. CleanMyMac
   Homebrew ignoruje, přitom u vývojářů žere GB.

5. **Sensitive file shredder** — bezpečné mazání citlivých souborů (s poctivou poznámkou,
   že na SSD/APFS je „shred" jiný než na HDD — nabídne FileVault-aware přístup).

6. **Config profile / MDM & extensions audit** — jaké konfigurační profily, kernel/system
   extensions, widgety a Safari rozšíření běží. Bezpečnostně cenné, nikdo to hezky nedělá.

7. **Duplicitní & podobné fotky (perceptual hash)** — najde nejen 1:1 duplicity, ale i
   „skoro stejné" fotky/screenshoty. Plus úklid složky Screenshots.

8. **Old installers & disk images** — staré `.dmg`/`.pkg` v Downloads, které už nepotřebuješ.

9. **Broken items finder** — rozbité symlinky, osiřelé prefs, neplatné login items.

10. **Weekly digest** — volitelný lokální report „tento týden: uvolněno X GB, disk roste
    o Y GB/týden, N appek k updatu". Bez cloudu, jen lokální notifikace.

11. **Menu bar quick actions** — nejčastější akce přímo z lišty bez otevření okna.

12. **„Explain this" u každého nálezu** — proč je bezpečné to smazat / co to je.

---

## Poznámka k „System Tune-up" / „RAM optimalizaci"
CleanMyMac tu do velké míry prodává placebo. Kestrel dělá jen věci s reálným efektem
(maintenance skripty, purgeable, index rebuild) a **nikdy neslibuje „zrychlení RAM"**.
Čestnost = feature.
