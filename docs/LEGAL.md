# Právní stránka a distribuce

> Nejsem právník; tohle je praktický přehled, ne právní rada. U prodeje ve větším
> zvaž konzultaci.

## Smí se: napodobit funkci
Funkčnost software se autorským právem **nechrání** — chrání se konkrétní vyjádření
(zdrojový kód, texty, grafika, ikony, jedinečný vizuál). Napsat vlastní cleaner
se stejnými funkcemi jako komerční cleanery je legální.

## Nesmí se: převzít vyjádření konkrétního cleaneru
- ❌ Kód (ani dekompilovaný), ikony, obrázky, jejich texty/formulace.
- ❌ Layout/vizuál 1:1 (pixel-perfect klon). Inspirace ano, kopie ne.
- ❌ Jméno, logo či konkrétní texty chráněného komerčního cleaneru (ochranné známky jejich výrobců).
- ❌ Vydávat se za výrobce jiného cleaneru / naznačovat spojení.

## Naming (náš projekt)
- Pracovní název **Kestrel** je placeholder. Před vydáním ověř:
  - není to registrovaná ochranná známka v kategorii software (EUIPO / USPTO / ÚPV ČR),
  - volná doména a název na Homebrew/GitHubu,
  - nekoliduje s existující Mac utilitou.
- Vlastní ikona a wordmark. Nepoužívat Apple loga/„Mac" v názvu způsobem, co budí dojem
  oficiálního Apple produktu (Apple má guidelines na použití „Mac"/„for Mac").

## Licence třetích stran (POZOR)
- **ClamAV** — licencováno pod **GPLv2**. Pokud ho *linkuješ/bundluješ* a distribuuješ,
  GPL se může vztáhnout na distribuci → buď:
  - drž AV část jako oddělený GPL komponent / volej ho jako samostatný proces (ne linkování), nebo
  - celý projekt uvolni pod kompatibilní licencí. Vyřeš PŘED prodejem.
- **YARA** — BSD-3-Clause, benevolentní, OK i pro placené.
- **Sparkle** (auto-update) — MIT-like, OK.
- Vždy přilož NOTICE se všemi licencemi third-party.

## Vlastní licence projektu
- Rozhodnutí: **MIT** (max. adopce) vs. **GPL** (nutné, pokud staticky linkuješ ClamAV)
  vs. dual-license (OSS + placená komerční). Sladit s bodem ClamAV výše.

## Distribuce na macOS
- **Mimo App Store (doporučeno pro cleaner):**
  - Apple Developer Program **$99/rok**.
  - **Developer ID** podpis + **notarizace** (`notarytool`) + **stapling**, jinak
    Gatekeeper appku u ostatních uživatelů zablokuje.
  - Mazání souborů mimo sandbox → mimo App Store je to volnější.
- **App Store:** tvrdý **sandbox** — hluboké čištění systému a on-access AV tam
  prakticky neprojde review. Nevhodné pro tuhle appku.
- **Antivirus a entitlements:** on-access scanning / FSEvents na cizí složky může
  vyžadovat Full Disk Access od uživatele (udělí ručně v Nastavení). Žádné privátní API.

## Prodej „za pár korun"
- Legální. Modely: jednorázová licence, donationware, „open-source + placený
  podepsaný build" (lidé platí za pohodlí a notarizaci).
- Řeš DPH/účetnictví dle objemu (paddle/gumroad umí handle VAT MOSS pro EU).
- Nikdy nesmíš prodávat cizí IP (ClamAV definice mají vlastní podmínky — komerční
  užití definic ClamAV zkontroluj).

## Čestnost jako feature (a ochrana)
- Žádné falešné „malware found". Klamání spotřebitele = riziko i mimo autorské právo.
- Zero telemetry a plná transparentnost jsou zároveň marketingový i právní plus.
