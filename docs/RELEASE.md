# Release — podpis, notarizace, distribuce

Fáze 7. Kestrel se distribuuje mimo App Store, takže platí: **Developer ID podpis +
notarizace + stapling**. Bez toho Gatekeeper appku na cizím Macu zablokuje.

## 1. Sestavení app bundlu

```bash
./scripts/build-app.sh            # → dist/Kestrel.app (ad-hoc podpis, běží lokálně)
open dist/Kestrel.app             # menubar ikona (LSUIElement — bez Docku)
```

`build-app.sh` sestaví release binárku `kestrel-app`, složí `Kestrel.app` s
`Info.plist` (`LSUIElement=true` → menubar accessory) a **ad-hoc** ji podepíše, takže
běží na tvém stroji. Pro distribuci ale potřebuješ pravý Developer ID podpis níže.

## 2. Předpoklady pro distribuci
- Apple Developer účet ($99/rok).
- „Developer ID Application" certifikát v klíčence.
- Zaznamenané notarytool credentials:
  `xcrun notarytool store-credentials KESTREL_NOTARY --apple-id <id> --team-id <TEAM> --password <app-specific-pw>`

## 3. Podpis (hardened runtime)
```bash
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: Denis Pyš (TEAMID)" \
  dist/Kestrel.app
codesign --verify --strict --verbose=2 dist/Kestrel.app
```

## 4. Notarizace + stapling
```bash
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

## 7. Ikona / branding
Zatím menubar používá SF Symbol `bird.fill`. Před vydáním dodej **vlastní** `AppIcon.icns`
(NE od CleanMyMac — viz `docs/LEGAL.md`) do `Kestrel.app/Contents/Resources` a přidej
`CFBundleIconFile` do `Info.plist`.

## 8. Model vydání (rozhodnout)
OSS jádro (MIT, už je) + volitelně placené „pro" buildy, nebo donationware. Detaily a
právní rizika v `docs/LEGAL.md`.
