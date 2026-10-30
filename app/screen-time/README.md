# Automatic Screen Time (work in progress, not in the build yet)

Planned for the January update. Needs Apple's Family Controls (Distribution) approval
before it can ship in TestFlight/App Store builds, so these files are NOT added to the
Xcode project yet (the TestFlight build keeps working without them).

How it works
- `plugin/ScreenTimePlugin.swift`: Capacitor plugin the game calls from index.html
  (`Capacitor.Plugins.ScreenTime`): `status`, `authorize` (Face ID prompt, individual
  authorization), `pickApps` (Apple's picker; player chooses "All apps"), `start`, `minutesFor(day)`.
- `monitor/MonitorExtension.swift`: Device Activity Monitor extension
  (bundle ID `io.github.gamesbyvidal.lifetime.monitor`). iOS calls it each time the day's
  total passes another 15 minutes; it saves the highest step reached for that day in the
  shared App Group `group.io.github.gamesbyvidal.lifetime`.
- We never see which apps were used, and nothing leaves the phone.

To wire up (after approval, or for a development build on Matthew's registered iPhone)
1. Developer portal: App Group above; App IDs for app + `.monitor` with Family Controls + App Groups.
2. Add `plugin/` to the App target and `monitor/` as a new Device Activity Monitor
   extension target (scripts/add-screen-time-target.rb using the xcodeproj gem), with
   entitlements `com.apple.developer.family-controls` and the App Group, iOS 16+.
3. Add the extension's bundle ID to `ios_signing` in codemagic.yaml.
