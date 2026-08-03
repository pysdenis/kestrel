# HANDOFF — kde jsme a jak pokračovat

Tenhle soubor je „onboarding" pro pokračování vývoje (klidně v nové session ve VSCode).
Přečti ho celý, pak `CLAUDE.md` (invarianty), pak pokračuj podle roadmapy.

## Co je Kestrel
Vlastní macOS utilita pro údržbu — čestná náhrada CleanMyMacu pro osobní použití,
cílově open-core (jádro open-source + placené „pro" buildy). Nativní Swift.
Vize a filozofie v `README.md`, plný katalog funkcí v `docs/FEATURES.md`.

## Vývojové prostředí
- **VSCode** (ne Xcode). Rozšíření `swiftlang.swift-vscode` + `lldb-dap` nainstalována.
- Swift 6.1 přes Command Line Tools (Core + CLI nepotřebují plný Xcode).
- `.vscode/` má připravené build/test/debug konfigurace.
- Příkazy: `swift build`, `swift run kestrel-tests`, `swift run kestrel scan <cesta>`.

## Stav: Fáze 0 HOTOVÁ ✅ (2026-08-03)
Bezpečnostní základ postaven a ověřen end-to-end (22/22 testů zelených):
- `KestrelCore`: modely, `VaultService` (karanténa místo mazání + undo/purge),
  `AuditLog` (append-only JSON-lines), pipeline `Scanner → Classifier → Planner → CleanupExecutor`.
- `kestrel-cli`: `scan`, `clean [--apply]` (default dry-run), `vault list/undo/purge`, `audit`.
- Ověřeno: apply → vault → undo vrátí soubor i s obsahem; `unknown` se nikdy nemaže.

## Nepřekročitelné invarianty (detail v CLAUDE.md)
1. Dry-run default; skutečná akce jen s `--apply`.
2. Nikdy `rm` napřímo — vše přes `VaultService` do `~/.kestrel/vault/` + undo.
3. `unknown` / nízká confidence = nikdy nemazat.
4. Každá destruktivní akce → `AuditLog`.
5. Antivirus nikdy nestraší. Zero telemetry.
6. Testy na temp adresářích — nikdy nesahat na reálný `~/Library` v testech.

## Fáze 1 — čisticí jádro (dev-first) — ROZPRACOVÁNO (90 testů zelených)
Hotovo:
- **`SafetyGuard`** (`Safety/SafetyGuard.swift`): centrální blacklist (klíče, klíčenky,
  `.git`/`.svn`/`.hg`, Photos/Music knihovny, lockfiles, systémové cesty) — finální brána
  v `Planner`u, i kdyby classifier zaškobrtl. Review-only kategorie (`dupes`/`large`)
  se do „ukliď vše" nikdy nezametou (`Category.requiresExplicitSelection`).
- **`DevArtifactClassifier`**: dev-artefakty přes „project marker" (node_modules↔package.json,
  target↔Cargo.toml/pom.xml, Pods↔Podfile, .build↔Package.swift, venv↔pyvenv.cfg…).
  Generické názvy (build/dist/out/target) bez markeru = `unknown`. Distinktivní
  (node_modules, DerivedData, __pycache__) se věří podle jména.
- **`CacheLogClassifier`**: per-app Library cache/logy + dev-tool cache (npm, yarn, pnpm,
  pip, Cargo, Go, Gradle, Maven, CocoaPods, Homebrew). Stray projektové `.log` se nechají být.
- **`LargeOldClassifier`**: konfigurovatelné prahy (default 100 MB / 180 dní), review-only.
- **`DuplicateFinder`**: size → partial hash → full SHA-256; nechá jeden originál, vrací kopie.
- **`ScanCoordinator`**: jeden rekurzivní průchod, prořezává dev-artefakty i cache jednotky,
  najde i **vnořené** node_modules v monorepu; zbytek sbírá pro dupes/large.
- **Docker/Homebrew adaptery** (`External/`): advisory náhled reclaimable místa
  (`docker system df`, `brew cleanup --dry-run`), Kestrel sám nic nemaže (mimo vault).
  `CommandRunner` je injektovatelný → testy bez nainstalovaných nástrojů.
- **CLI**: `scan`/`clean` přes coordinator, breakdown po kategoriích, „Review (opt-in)"
  sekce, `--min-size/--min-age/--no-dupes/--no-large`, `kestrel docker`, `kestrel brew`.

Zbývá ve Fázi 1:
- **App uninstaller** (bundle + leftovers).
- Reálné provedení Docker/brew prune (mimo vault → potřebuje explicitní opt-in UX).

Pak Fáze 2 (Space Lens/přehled místa) → Fáze 3 (SwiftUI menubar GUI, tady přijde Xcode)
→ Fáze 4 (antivirus) → Fáze 5 (zbytek CleanMyMac sekcí) → Fáze 6 (extra) → Fáze 7 (release).
Detailní checklisty: `docs/ROADMAP.md`.

## Git & GitHub
- Repo má být **veřejné pod účtem `pysdenis`**.
- `gh` bývá přihlášené jako `denispys-fastest` → před vytvořením přepnout:
  `gh auth login` (nebo `gh auth switch`) na účet `pysdenis`, ověřit `gh api user --jq .login`.
- Pak: `gh repo create pysdenis/kestrel --public --source=. --remote=origin --push`.
- **Commit messages: čistě věcné, bez zmínek o AI/nástrojích.**

## Konvence
- Kód/identifikátory/commity anglicky; konverzace s Denisem česky.
- Malé tematické commity, build + testy zelené před commitem.
- Uživatelsky viditelné texty v CLI/GUI anglicky (kvůli mezinárodní prodejnosti).
