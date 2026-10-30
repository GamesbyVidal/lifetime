# Lifetime phone app ("Blip: Screen Time Game" on the App Store)

The App Store / Google Play version of Lifetime. It wraps the same game the website uses
(`../index.html`) with [Capacitor](https://capacitorjs.com), so the website and the app stay one game.

- `scripts/copy-web.js` copies the game into `www/` before each build.
- `ios/` and `android/` are the native projects. iPhone only (no iPad), portrait only.
- The iPhone app is built online by Codemagic using `../codemagic.yaml` (no Mac needed) and uploaded to TestFlight.
- In the app, `IS_APP` in index.html is true: the save is also kept in the app's own storage,
  "Put on home screen" and the calendar reminder card are hidden, share links point to the website,
  and stats go to GoatCounter under `/lifetime-app/` with events starting `lifetime-app-`.

Bundle ID: `io.github.gamesbyvidal.lifetime`

Local commands (need Node 22): `npm ci`, then `npm run sync` to copy the game into both apps.

## Gift shop (in-app purchases)

The shop tab only appears in the app (and when index.html is opened from a file or localhost
for testing, where "buying" is simulated). Purchases use StoreKit 2 through
`ios/App/App/StorePlugin.swift`, registered in `MainViewController.swift`.

Product IDs in App Store Connect (all Non-Consumable):
`blip.item.<key>` for single gifts (keys in `GIFT.ITEMS` in index.html) and
`blip.bundle.holiday` ($2.99), `blip.bundle.founder` ($4.99).
Prices load from Apple; until products exist (and the Paid Apps agreement is active)
the shop shows "opens soon" and lets players try things on.
