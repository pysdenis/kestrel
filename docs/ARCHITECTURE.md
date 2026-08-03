# Architektura

## Přehled vrstev

```
┌──────────────────────────────────────────────────────────┐
│  KestrelApp (SwiftUI, NSStatusItem + NSPopover)           │  UI vrstva
│  kestrel-cli  (ArgumentParser)                            │  CLI vrstva
├──────────────────────────────────────────────────────────┤
│                      KestrelCore                          │  logika (bez UI)
│  Scan · Classify · Plan · Vault · Clean · Stats · AV      │
├──────────────────────────────────────────────────────────┤
│  macOS API: IOKit, Mach, statfs, CoreWLAN, DiskArb,       │  systém
│  FSEvents, DiskArbitration, NetworkExtension(opt)          │
└──────────────────────────────────────────────────────────┘
```

**Zlaté pravidlo:** `KestrelCore` neimportuje SwiftUI/AppKit. UI i CLI jsou tenké
slupky, které volají Core a jen renderují výsledek. Tím je logika testovatelná
a znovupoužitelná.

## Klíčové moduly v KestrelCore

### Scan → Classify → Plan → Apply (pipeline)
Destruktivní operace nikdy nejsou jeden krok. Vždy:

1. **Scanner** — projde cesty, vrátí `[FileEntry]` (path, size, mtime, typ).
2. **Classifier** — přiřadí `Category` (safeCache, devArtifact, duplicate, largeOld,
   appLeftover, unknown…) + `Confidence`. Nejasné = `unknown` → nikdy nemazat.
3. **Planner** — z klasifikace vytvoří `CleanupPlan` (co, kolik místa, kam do vaultu).
4. **Executor** — až s `apply` provede plán přes `VaultService`, zapíše audit.

### VaultService (srdce bezpečnosti)
- `move(entry) -> VaultRecord` — přesun do `~/.kestrel/vault/<ts>/` + manifest JSON
  (původní cesta, oprávnění, čas).
- `undo(session)` — obnoví z vaultu na původní místo.
- `purge(olderThan:)` — teprve tady reálný `rm`, po retenci (default 14 dní).
- Vault i cíl na stejném volume → přesun je rychlý (rename), ne kopie. Cross-volume
  fallback = copy+verify+delete.

### AuditLog
- JSON-lines append do `~/.kestrel/audit.log`. Neměnný, jen přidává.
- Každý záznam: `{ts, action, category, paths[], bytes, result, sessionId}`.

### StatsCollector
- `diskUsage()` — `statfs` / `URLResourceValues`.
- `memoryPressure()` — Mach `host_statistics64` (`vm_statistics64`).
- `cpuLoad()` — `host_processor_info`.
- `battery()` — IOKit `IOPSCopyPowerSourcesInfo` + `IORegistry` (health, cycles).
- `network()` — `getifaddrs` čítače + CoreWLAN SSID.
- `volumes()` — `FileManager.mountedVolumeURLs` + DiskArbitration.
- **Snapshots** — denní snímek využití do `~/.kestrel/snapshots/` pro trend/předpověď.

### DiskMap (přehled místa)
- Rekurzivní velikost složek (paralelně, s early-cutoff pro drobné).
- Výstup pro treemap/sunburst; cache výsledků + inkrementální refresh přes FSEvents.

### PowerAuditor (extra feature)
- Parsuje `pmset -g assertions` a `log show` wake reasons.
- Identifikuje, kdo brání spánku / budí Mac. (Řeší reálný problém přehřívání v tašce.)

### AntivirusEngine
- `ClamAVAdapter` — bundlovaný `clamd`/`clamscan`, auto-update `freshclam`.
- `YaraScanner` — sada pravidel pro Mac malware/adware.
- `Heuristics` — nepodepsané binárky, spuštění z Downloads, dylib injection,
  podezřelé LaunchAgents.
- `SystemProtectionStatus` — čte XProtect/Gatekeeper (`spctl`, `system_profiler`).
- `QuarantineReader` — soubory s `com.apple.quarantine`.
- On-access: `FSEventsWatcher` na Downloads/Desktop → sken nových souborů.

### RulesEngine (extra feature)
- Deklarativní pravidla (`when → do`), spouštěná ručně nebo přes `launchd`.
- Např. `{ match: Downloads, olderThan: 30d, action: toVault }`.
- Vše prochází stejnou Scan→Plan→Apply pipeline (žádná zkratka kolem vaultu).

## GUI (KestrelApp)
- `NSStatusItem` v liště → klik otevře `NSPopover` se SwiftUI dashboardem.
- Dlaždice = SwiftUI komponenty napojené na `StatsCollector` (async, refresh timer).
- Těžké operace (sken, úklid) v samostatném okně/sheetu, ne v popoveru.
- Live hodnoty přes `AsyncStream` z Core; UI jen renderuje.

## CLI (kestrel-cli)
```
kestrel scan [--category dev|cache|dupes|large|all]      # jen report
kestrel clean --category cache [--apply]                 # default dry-run
kestrel vault list | undo <session> | purge
kestrel stats [disk|mem|cpu|battery|net]
kestrel map [path]                                        # treemap v terminálu
kestrel av scan <path> [--full]
kestrel power assertions                                  # kdo brání spánku
kestrel audit tail
```

## Závislosti (minimalizovat)
- `swift-argument-parser` (CLI).
- ClamAV + YARA jako bundlované binárky/knihovny (viz `docs/LEGAL.md` k licencím).
- Jinak co nejvíc čistý systém — méně závislostí = snazší notarizace a údržba.
