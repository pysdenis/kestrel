# CLAUDE.md — pokyny pro vývoj Kestrelu s Claude Code

Tenhle soubor čti **vždy** na začátku práce na projektu. Definuje nepřekročitelné
invarianty. Jsme utilita, která **maže soubory** a **skenuje na malware** — chyba
tu znamená ztrátu dat nebo falešný pocit bezpečí. Podle toho se chováme.

## Jazyk
- Kód, identifikátory, commit messages, PR: **anglicky**.
- Komentáře smysluplné, ne popisné-samozřejmé.
- Konverzace s uživatelem (Denis): **česky**.

## Bezpečnostní invarianty (NIKDY neporušit)
1. **Žádná destruktivní operace bez dry-run defaultu.** Skutečné smazání vyžaduje
   explicitní `--apply` (CLI) nebo potvrzení v UI.
2. **Nikdy `rm` napřímo.** Vše jde přes `VaultService` → přesun do
   `~/.kestrel/vault/<timestamp>/` s manifestem pro undo. Trvalé smazání až po retenci.
3. **Whitelist toho, co je bezpečné smazat; blacklist toho, co ne.** Nikdy nemazat
   v `/System`, `/Library` (systémové), uživatelské dokumenty, zdrojové kódy,
   `.git`, klíče, klíčenky, `~/Library/Keychains`, Photos knihovny bez explicitní volby.
4. **Dev-junk mazání smí smazat jen znovu-generovatelné artefakty** (`node_modules`,
   `DerivedData`, `target/`, `dist/`, `build/`, `.venv`), NIKDY zdrojáky ani lockfiles.
5. **Každá akce → audit log** (`~/.kestrel/audit.log`, JSON lines): akce, cesty,
   velikost, čas, výsledek.
6. **Antivirus nikdy nestraší.** Report obsahuje jen reálné nálezy s cestou k důkazu
   (pravidlo/hash). Když je čisto, řekni „čisto". Žádné vymyšlené „doporučené hloubkové skeny".
7. **Zero telemetry.** Nic neodchází ze zařízení. Žádný účet, žádné analytics.
   **Výjimka (opt-in):** volitelný AI asistent (Gemini) — defaultně vypnutý, aktivní
   jen když uživatel dodá vlastní API klíč; posílá **pouze metadata** (názvy, velikosti,
   kategorie, dotaz), **nikdy obsah souborů**. Speed test kontaktuje Cloudflare jen na
   akci uživatele a nic neposílá. Vše ostatní zůstává offline.

## Konvence kódu
- **Swift 5.9+**, SwiftUI pro UI, Swift Package Manager.
- Vrstvení: `KestrelCore` (žádné UI importy) ← `kestrel-cli` a `KestrelApp`.
- Veškerá logika testovatelná bez UI. Cílová coverage Core: vysoká.
- Async/await pro I/O. Žádné blokování main threadu v UI.
- Systémová data přes veřejná API (IOKit, Mach `host_statistics64`, `statfs`,
  CoreWLAN, DiskArbitration, FSEvents). Žádné privátní API (kvůli notarizaci).
- Chyby: typed errors (`enum ...: Error`), žádné `try!`, žádné `fatalError` na runtime cestách.

## Struktura commitů
- Malé, tématické commity. Jeden invariant/feature na commit.
- Před commitem: build + testy zelené. Destruktivní cesty musí mít test na dry-run.

## Testování destruktivních cest (povinné)
- Každá mazací funkce: test že v dry-run **nic nesmaže** a vrátí správný plán.
- Test že `apply` přesune do vaultu (ne `rm`) a zapíše manifest.
- Test undo: obnoví z vaultu na původní cestu.
- Použij dočasné adresáře (nikdy nesahej na reálný `~/Library` v testech).

## Co dělat, když si nejsi jistý
- Raději méně smazat než omylem něco důležitého. Když je klasifikace souboru
  nejasná → nechej ho a označ jako „neznámé, přeskočeno".
- U nové kategorie junku napřed napiš klasifikátor + testy, teprve pak zapoj do úklidu.

## Práce po fázích
Postupuj podle `docs/ROADMAP.md`. Neskákej do GUI/antiviru, dokud nestojí Core + vault
+ audit + dry-run infra (Fáze 0). Pořadí: **Core → CLI → GUI → AV → extra**.

## Právní připomínka
Nepoužívej NIC z CleanMyMac (kód, texty, ikony, layout 1:1, jméno). Vlastní branding.
Detaily `docs/LEGAL.md`.
