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

## Další krok: Fáze 1 — čisticí jádro (dev-first)
Pořadí dle Denisovy niky (vývojářský úklid má přednost):
1. Rozšířit classifiery: cache/logy (per-app), **dev-artefakty** (node_modules, DerivedData,
   .venv, target, dist, build, .gradle, CocoaPods), **Docker** (`docker system df`/prune náhled),
   **Homebrew** (`brew cleanup`, staré verze).
2. **Duplicity**: size → partial hash → full hash.
3. **Velké & staré soubory**: konfigurovatelné prahy.
4. Každý classifier = vlastní typ + testy (napřed test, pak zapojení do plánu).
5. Rozšířit CLI výstup o breakdown po kategoriích.

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
