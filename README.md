# Kestrel 🦅

> Lehká, čestná a rychlá utilita pro údržbu macOS. Menubar dashboard, chytré
> čištění místa, čestný antivirus a nástroje, které komerční cleanery obvykle nemají.
>
> Nativní **Swift/SwiftUI**. Žádný Electron, žádné „strašení", žádné mazání naslepo.
> Vše, co Kestrel udělá, je **předem vidět, potvrditelné a vratné**.

---

## Proč tohle vzniká

Většina komerčních Mac „cleanerů" je z velké části hezký obal nad věcmi, které macOS
umí sám — plus marketing (vymyšlené „malware found", placebo „optimalizace RAM").
Kestrel jde opačně:

1. **Čestně** — žádné vymyšlené hrozby, žádná placebo tlačítka. Když je čisto, řekne „čisto".
2. **Bezpečně** — dry-run defaultně, trezor místo `rm`, plný audit log, allowlist.
3. **Lépe pro vývojáře** — node_modules, DerivedData, `.venv`, `target/`, Docker, package cache.
   Tohle bere nejvíc místa a běžné cleanery to ignorují.
4. **Lehce a offline** — jedna nativní menubar appka, **nula telemetrie**, žádný účet.

---

## Nepřekročitelná pravidla (bezpečnostní invarianty)

| Princip | Co to znamená |
|---|---|
| **Dry-run first** | Každá destruktivní operace je defaultně jen náhled; skutečné smazání vyžaduje `--apply` (CLI) / potvrzení (GUI). |
| **Trezor, ne `rm`** | Vše jde do `~/.kestrel/vault/` s manifestem pro undo; trvale se maže až po retenci. |
| **Nic naslepo** | Vždy: sken → seznam s velikostmi → volba uživatele. |
| **Allowlist** | Cesty, kterých se Kestrel nikdy nedotkne (`SafetyGuard`), + ochrana systému/klíčů/`.git`. |
| **Audit log** | Každá akce do `~/.kestrel/audit.log` (co, kdy, kolik, odkud kam). |
| **Žádné strašení** | Antivirus hlásí jen reálné nálezy s důkazem. |
| **Nula telemetrie** | Nic neopouští Mac. Výjimky (opt-in, jen metadata): AI asistent přes Gemini a kontrola aktualizací na GitHubu. On-device AI neposílá vůbec nic. |

---

## Moduly (GUI)

Vlastní „Precision" design — žádné výchozí Apple ovládací prvky. 15 sekcí:

- **Smart Care** — jedním klikem: uvolnitelné místo + ochrana + malware + aktualizace aplikací, volitelné kroky.
- **Dashboard** — Mac Health (rozklikací), disk/paměť/CPU/baterie/síť, předpověď místa, „co sráží skóre → oprav".
- **Cleanup** — cache/logy/dev-artefakty/duplicity/privacy, per-položkový výběr + reveal, přes trezor, **AI plán úklidu** (3 koše).
- **Space** — treemap disku, **Žrouti místa** (DerivedData, iOS zálohy, Caches…), **„Co narostlo"** (viník za 7/30 dní), SMART zdraví disku.
- **Energy** — spotřeba podle aplikace (jméno + ikona) + AI „proč to žere".
- **Security** — čestný AV (EICAR + heuristika, karanténa), **Security Posture** + **Hardening s one-tap fixy**, **ransomware kanárek** (živě), **inspektor podpisu appek**, **síťová spojení** (read-only), **provenience Downloadů**.
- **Applications** — odinstalace i se zbytky (přes trezor), nepoužívané appky, aktualizace přes Homebrew.
- **Permissions** — **mapa expozice** appek (kamera/mik/FDA…), reverzní pohled „podle oprávnění", one-hop revoke.
- **Tools** — Trash, App Leftovers, Old Installers, Screenshots, **Similar Images**, **Duplicate Files** (+ APFS dedupe), **Největší soubory**, **iOS zálohy**, **Spící projekty** (git-aware), **Developer caches** (Xcode DeviceSupport/simulátory…), **Rozšíření a doplňky**, **Systémové tweaky** (vratné), **Privacy**, Cloud Cleanup, Secrets scanner, Login items, Maintenance.
- **Automation** — deklarativní pravidla (náhled, přes trezor, plánované přes launchd), **pravidlo z věty** (NL builder).
- **Assistant** — čestný AI chat; **on-device** (Apple Foundation Models, offline), **Ollama** (lokální, zdarma) nebo Gemini.
- **Time Machine** — procházatelná, reverzibilní historie každého úklidu; obnov celou relaci i jediný soubor.
- **My Activity** — co Kestrel udělal (z audit logu), export reportu (.md).
- **Settings** — jazyk (CZ/EN), auto-update, allowlist, správa trezoru.

## Killer diferenciátory 🏆

1. **Cleanup Time Machine** — skutečné granulární undo jakéhokoli úklidu. „Cleaner, kterého nemůžeš litovat."
2. **Lokální AI (offline)** — asistent přes Apple Foundation Models **nebo Ollamu**: rady i **AI plán úklidu bez jediného síťového požadavku**.
3. **Ransomware kanárek** — návnady v Documents/Desktop/Pictures; přepis/smazání = okamžitý alert. Jen detekce, nikdy nesahá na tvoje data.
4. **Mapa expozice appky** — kdo vidí tvoji kameru/mik/disk, zvýraznění citlivých, one-hop revoke.
5. **Security hardening + fix** — čestný checklist ochran s deep-linkem přímo na dané nastavení.
6. **Duplicity → APFS klon** — uvolní místo, ale **nechá oba soubory** (copy-on-write). Nemaže.
7. **„Co narostlo"** — culprit timeline: viník růstu místa za 7/30 dní. **Pravidlo z věty** — NL → automatizace přes trezor.
8. **Spící projekty** (git-aware) — regenerovatelný balast seskupený podle git repa + stáří commitu; uvolni z projektů, kterých ses měsíce nedotkl.
9. **Vault fire-drill** — Kestrel *dokáže*, že jeho undo funguje (ověří bytes vs. manifest). Nikdo jiný svou záchrannou síť neprokazuje.
10. **Inspektor podpisu appek** — Developer ID / ad-hoc / neplatný, čestně (bez false-positive strašení).

Plus: dev-mode úklid, trezor+undo, storage forecast, power/wake auditor, login-item auditor,
rules engine, plně skriptovatelné CLI, bandwidth monitor, „explain this", perceptual-hash fotky,
secrets scanner, system-extensions audit, self-update přes GitHub Releases.

---

## Lokální AI zdarma (Ollama) 🧠

Asistent umí běžet **plně offline a zdarma** přes [Ollama](https://ollama.com) — model běží na tvém
Macu, žádný API klíč, žádná data neopustí zařízení. Kestrel Ollamu **detekuje sám**; jakmile běží
s nějakým modelem, badge u asistenta se přepne na `Ollama · <model>`.

**Nejsnadněji přímo z appky:** otevři **Assistant** → *Nainstalovat Ollamu* → *Stáhnout AI model*.
Kestrel stáhne doporučený model a sám se zapne. Nebo z terminálu:

```bash
brew install ollama            # nebo stáhni z ollama.com
brew services start ollama     # server na localhost:11434 (naběhne i po restartu)
ollama pull qwen3:8b           # ~5,2 GB, dobrá čeština i logika (doporučeno)
```

Kestrel si sám vybere **kvalitní vícejazyčný model** (qwen3:8b, qwen2.5:7b, gemma2, llama3.1) — malé modely
(3B) totiž češtinu komolí. Těžké coder/reasoning modely nechává na tvoje vlastní použití. Model se
po ~90 s nečinnosti **sám uvolní z RAM**, takže na pozadí nebere baterku ani paměť.

> ℹ️ **DMG neobsahuje Ollamu ani model** (byl by obří) — appka funguje i bez ní, jen bez lokální AI.
> Lokální AI je volitelná: doinstaluješ ji výše uvedeným postupem, jednou. Vše ostatní je offline.

**Pořadí backendů:** on-device (Apple Foundation Models) → Ollama → Gemini. První dostupný vyhrává.

> Doporučení podle RAM: **8 GB** → `llama3.2:3b` / `phi3.5` (lehčí, čeština slabší); **16 GB** →
> `qwen3:8b` na asistenta + `qwen2.5-coder:7b` na kód; **32 GB+** → `qwen2.5-coder:32b`. Velký
> model na malé RAM swapuje a je pomalý — proto Kestrel pro sebe volí ten vhodný k dané RAM.

---

## Architektura

```
kestrel/
├─ KestrelCore/   # Swift package — veškerá logika, bez UI (scan/clean/av/stats/vault)
├─ kestrel-cli/   # CLI nad Core (dry-run default, skriptovatelné)
├─ KestrelApp/    # SwiftUI menubar + okno nad Core
├─ Resources/     # vlastní ikona (AppIcon.icns), definice
└─ docs/
```

Jádro (`KestrelCore`) nezná UI. CLI i GUI jsou tenké slupky nad ním → testovatelné,
znovupoužitelné, snadné na code review. Detaily v `docs/ARCHITECTURE.md`.

---

## Instalace a použití

Vyžaduje Swift 5.9+ (Command Line Tools stačí; Xcode netřeba pro build).

```bash
swift build                # KestrelCore + kestrel (CLI) + kestrel-app (GUI)
swift run kestrel-tests    # testová sada (dependency-free runner) — 289 zelených
swift run kestrel help     # přehled CLI příkazů
```

### GUI (menubar + okno)
```bash
./scripts/build-app.sh     # → dist/Kestrel.app (ad-hoc podpis, běží lokálně)
open dist/Kestrel.app
```

### CLI (vše dry-run defaultně)
`clean`/`uninstall`/`orphans` nic nesmažou bez `--apply`, a i pak jdou soubory do trezoru
(vratné přes `vault undo`).
```bash
kestrel scan ~/Developer
kestrel clean ~/Developer --category dev --apply   # jen znovu-generovatelné → trezor
kestrel uninstall Slack                            # appka + zbytky → trezor
kestrel map ~/Library --depth 2                    # treemap v terminálu
kestrel av scan ~/Downloads                        # čestný sken (EICAR + heuristika)
kestrel secrets ~/myproject                        # uniklé klíče/tokeny (redigované)
kestrel smartscan                                  # jednotlačítkový přehled
```

---

## Distribuce (zdarma, bez Apple účtu)

Kestrel se šíří přes **GitHub Releases** s **in-app auto-updatem** — Apple Developer účet netřeba.

```bash
bash scripts/release-oss.sh --publish   # nepodepsaný .dmg+.zip + GitHub Release
```
Nepodepsané balíčky Gatekeeper po stažení karanténuje → otevři pravým klikem → *Otevřít*
(nebo `xattr -dr com.apple.quarantine Kestrel.app`). Build ze zdroje Gatekeeper obchází úplně.

In-app updater čte `releases/latest` (read-only GET, žádná data ven) a nabídne stažení.
Developer ID podpis + notarizace (`scripts/release.sh`) zůstává připravený pro budoucí App-Store-mimo distribuci.

---

## Vývoj

Core + CLI se vyvíjí plně ve VSCode (Xcode netřeba pro build; GUI se kompiluje bez Xcode,
jen SwiftUI previews a finální notarizace by Xcode chtěly).

```bash
swift build && swift run kestrel-tests
```

Pravidla, konvence a invarianty: `CLAUDE.md`. Roadmapa a checklisty: `docs/ROADMAP.md`.
Právní/branding poznámky: `docs/LEGAL.md`.

---

*Lokalizováno CZ/EN · 289 testů zelených · 0 build varování · nula telemetrie.*
