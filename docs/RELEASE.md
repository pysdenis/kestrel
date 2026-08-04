# Release — podpis, notarizace, distribuce

Fáze 7. Kestrel se distribuuje mimo App Store, takže platí: **Developer ID podpis +
notarizace + stapling**. Bez toho Gatekeeper appku na cizím Macu zablokuje.

## 1. Sestavení app bundlu

```bash
./scripts/build-app.sh            # → dist/Kestrel.app (ad-hoc podpis, běží lokálně)
open dist/Kestrel.app             # okno + Dock ikona + menubar health-ring
```

`build-app.sh` sestaví release binárku `kestrel-app`, složí `Kestrel.app` s `Info.plist`
(`LSUIElement=false` → plnohodnotná app s oknem, Dock ikonou a menubar položkou), vloží
`AppIcon.icns` a **ad-hoc** ji podepíše, takže běží na tvém stroji. Pro distribuci ale
potřebuješ pravý Developer ID podpis níže.

## 2. Předpoklady pro distribuci
- Apple Developer účet ($99/rok).
- „Developer ID Application" certifikát v klíčence.
- Zaznamenané notarytool credentials:
  `xcrun notarytool store-credentials KESTREL_NOTARY --apple-id <id> --team-id <TEAM> --password <app-specific-pw>`

## 3. Jedním příkazem: `scripts/release.sh`
Podpis (hardened runtime) → notarizace → stapling → `.dmg` (s odkazem na /Applications).
Skript **nic neposílá**, dokud nedodáš oba env parametry — bez nich jen vypíše, co chybí.
```bash
SIGN_IDENTITY="Developer ID Application: Denis Pyš (TEAMID)" \
NOTARY_PROFILE="KESTREL_NOTARY" \
bash scripts/release.sh
# → dist/Kestrel-<verze>.dmg (notarizovaný, staplovaný, podepsaný)
```

## 4. Ručně (co release.sh dělá pod kapotou)
```bash
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: Denis Pyš (TEAMID)" dist/Kestrel.app
codesign --verify --strict --verbose=2 dist/Kestrel.app
ditto -c -k --keepParent dist/Kestrel.app dist/Kestrel.zip
xcrun notarytool submit dist/Kestrel.zip --keychain-profile KESTREL_NOTARY --wait
xcrun stapler staple dist/Kestrel.app
spctl -a -vvv --type exec dist/Kestrel.app   # → "accepted, source=Notarized Developer ID"
```

## 5. CLI binárka
`kestrel` (CLI) se distribuuje samostatně (Homebrew tap / GitHub Release). Podepiš stejným
Developer ID (`codesign --options runtime --timestamp`) a notarizuj jako samostatný archiv.

## 6. Zdarma: GitHub Release + in-app auto-update — ✅ hotovo
Pro osobní/OSS testovací distribuci **bez Apple účtu**. Artefakty jsou nepodepsané, takže
po *stažení* je macOS uvrhne do karantény — kamarád otevře pravým klikem → Otevřít
(nebo `xattr -dr com.apple.quarantine Kestrel.app`). Build ze zdroje Gatekeeper obchází úplně.

**Vydání jednoho buildu:**
```bash
bash scripts/release-oss.sh            # → dist/Kestrel-<v>.dmg + .zip (nepodepsané)
bash scripts/release-oss.sh --publish  # + vytvoří GitHub Release v<v> (potřebuje gh auth)
```
`--publish` je záměrně explicitní — bez něj skript jen sestaví artefakty a vypíše příkaz.

**In-app auto-update** (`KestrelCore.SelfUpdate` + Settings → Aktualizace):
- Čte `https://api.github.com/repos/pysdenis/kestrel/releases/latest`, porovná semver s
  `Kestrel.version`. Read-only GET, **žádná data neodcházejí** (jen IP, jako u každého stažení).
- Toggle „Automaticky kontrolovat aktualizace" (default zap., protože jde o osobní build) —
  jediný automatický síťový požadavek v celé appce. Vypnutelný.
- Novější verze → banner nad obsahem + karta v Settings: „Stáhnout" stáhne `.dmg`/`.zip` do
  Stažených a odhalí ve Finderu (žádný in-place swap běžící appky). „Poznámky k vydání" otevře
  stránku releasu.
- Nová verze = zvedni `Kestrel.version` v `Sources/KestrelCore/Version.swift`, commitni,
  `bash scripts/release-oss.sh --publish`.

Pozn.: `AppUpdater.sparkleFeed(of:)` (čtení `SUFeedURL`) zůstává pro budoucí Sparkle cestu,
až bude podpis (Sparkle vyžaduje EdDSA/Developer ID pro bezpečné auto-instalace).

## 7. Ikona / branding — ✅ hotovo
Vlastní `Resources/AppIcon.icns` (teal→indigo squircle, bílý pták v health-gauge prstenci —
stejné brand marky jako UI, žádné CleanMyMac assety, viz `docs/LEGAL.md`). `build-app.sh` ji
kopíruje do bundlu a `Info.plist` má `CFBundleIconFile=AppIcon`. Regenerace z brand marků:
```bash
bash scripts/make-icns.sh   # scripts/make-icon.swift → 1024pt master → iconset → .icns
```
Menubar používá **živý health-ring** (proporce podle Mac Health skóre), ne statický symbol.

## 8. Model vydání (rozhodnout)
OSS jádro (MIT, už je) + volitelně placené „pro" buildy, nebo donationware. Detaily a
právní rizika v `docs/LEGAL.md`.
