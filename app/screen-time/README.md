# Automatic Screen Time

Apple approved the Family Controls (Distribution) entitlement on 2026-10-31 (request 4H32ZLL24N),
so automatic tracking can ship in TestFlight and App Store builds.

How it works
- `app/ios/App/App/ScreenTimePlugin.swift`: Capacitor plugin the game calls from index.html
  (`Capacitor.registerPlugin('ScreenTime')`, registered in MainViewController): `status`, `authorize`
  (individual authorization), `pickApps` (Apple's picker: tick All, then search for Safari and add it), `start`, `minutesFor(day)`.
  The daily counter uses the picked categories + apps, WITHOUT websites (Safari's own time covers them;
  counting both double counts). Picked categories without Safari missed ~1h on Nov 6. A no-filter event
  (build 21) counted idle time (12h30m vs 1h10m on Nov 8), so never use it for the real count.
- `app/ios/App/BlipMonitor/MonitorExtension.swift`: Device Activity Monitor extension (target
  `BlipMonitor`, bundle ID `io.github.gamesbyvidal.lifetime.monitor`). iOS calls it each time the
  day's total passes another 5 minutes; it saves the highest step reached for that day in the
  shared App Group `group.io.github.gamesbyvidal.lifetime`.
- We never see which apps were used, and nothing leaves the phone.
- In the game: Settings > "Automatic screen time" > Connect Screen Time. Check-in then shows
  the day's number from Screen Time instead of the slider. If Screen Time hasn't sent a number
  yet, the slider comes back with a note.
- Minimum iOS is now 16 (needed for individual authorization).

One-time Apple setup (developer.apple.com > Certificates, Identifiers & Profiles)
1. Identifiers > App Groups: register `group.io.github.gamesbyvidal.lifetime`.
2. App ID `io.github.gamesbyvidal.lifetime`: turn on Family Controls (Distribution) and App Groups
   (choose the group above).
3. Register App ID `io.github.gamesbyvidal.lifetime.monitor` (name "Blip Monitor") with the same
   two capabilities.
4. Profiles: regenerate the App Store profile for the app (its old one is invalid after step 2) and
   create an App Store profile for `.monitor`, both with the `lifetime_distribution` certificate.
5. Codemagic > Team settings > Code signing identities > iOS provisioning profiles: fetch both
   profiles from the Developer Portal. `ios_signing` in codemagic.yaml picks up profiles for the
   app's bundle ID and the extension (same prefix).

Compliance (legal review 2026-11-01, /mnt/project-files/lifetime/legal/screen-time-compliance.md),
done in index.html via `stUsed()`, which is true once any day in this life came from Screen Time:
1. Analytics: trophy-st*/tb* events are sent as a plain "trophy" event.
2. Share text and pictures: no goal squares, streak, kite or Time back hours. Trophy shares for
   streak and time-back trophies share the Blip instead. No "Post my time back" button.
3. #meet= links: no `st` (streak) or `m` (goal met count).
4. Challenge a friend: no time-back numbers in the invite text.
5. Denied or revoked permission switches back to entering the number by hand.
Tracking is free and never changes what the shop sells or when it's shown.

Legal review of e85c8b1 (2026-11-01): OK for TestFlight. Privacy label unchanged; policy docx updated.
Before the App Store: live privacy.html URL; App Review note: "Settings > Automatic screen time >
Connect Screen Time. Uses Family Controls individual authorization; the player picks all categories plus
Safari in Apple's picker; DeviceActivity monitor only (5-minute thresholds). No app blocking. Data stays on device. Manual entry works if permission is
declined."; store description and What's New lead with managing your own screen time.
Never make an analytics event depend on the day's verdict.
Before submission also (Lawyer 2026-11-06): remove the TestFlight "picked", "web", "all" watchers, the
diag- keys, and the Screen Time check log. (The picker stays: the no-filter counter failed.)

Shop review note (add to the App Review note): "Style items (bow, tiara, dresses, Style starter set)
appear in Shop > Style when the Blip is a girl (choose Girl at setup). Baby clothes appear in Shop >
Baby while the Blip is a baby (ages 0-4). Owned items stay in the Closet and any grown Blip can wear them."
