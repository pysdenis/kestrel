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

## 6. Auto-update
Dvě cesty:
- **GitHub Releases** + jednoduchý „check latest tag" v appce (bez závislostí).
- **Sparkle** (open-source) s vlastním appcastem — `AppUpdater.sparkleFeed(of:)` už umí
  číst `SUFeedURL`, takže integrace je přímočará.

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
