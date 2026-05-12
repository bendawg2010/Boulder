# 🪨 Boulder

A pet rock for your focus. It can't die. It just grows.

Boulder is an anti-anxiety focus app for macOS. You have a pet rock named Boulder. Boulder needs nothing. Boulder can't die. But every minute you focus, Boulder grows a fraction of a pixel. After 6 months of focusing, you've built a small mountain. After a year, a landmark.

This subverts the Forest / Focus Friend genre: **no death mechanic, no guilt, no punishment for breaking focus.** Pure slow accretion. The chill productivity app.

→ Live site: [boulder.pages.dev](https://boulder.pages.dev)
→ Tip: [cash.app/$Dryeetsolutions](https://cash.app/$Dryeetsolutions)

## Tech

- Swift + SwiftUI + xcodegen (`project.yml` is the source of truth)
- Sparkle 2.x for auto-updates
- Ad-hoc signed (`-`) — free, no Developer ID
- macOS 14+, LSUIElement menubar app
- MIT licensed

## Build

```bash
./scripts/build.sh                  # build Boulder.app
./scripts/build-dmg.sh              # package as Boulder.dmg
./scripts/release.sh 1.0.1 "Notes"  # bump version + build + appcast
```

The first release needs Sparkle's CLI tools vendored at `scripts/sparkle/`. Copy the `bin/` folder from any other gravy project (NotchPop, WallPop). Then generate an EdDSA keypair with `./scripts/sparkle/bin/generate_keys`, paste the public half into `project.yml` (`SUPublicEDKey`).

## Deploy site

```bash
cd website
npx wrangler pages deploy . --project-name=boulder --branch=main --commit-dirty=true
```

## Notchyverse

Boulder is canon in the Notchyverse alongside FocusDex, SkyJournal, Campfire, NotchPop, WallPop. FocusDex players who also use Boulder unlock the Pebblekin → Boulderkin creature line.
