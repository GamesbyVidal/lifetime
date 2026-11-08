import Foundation
import Capacitor
import SwiftUI
import FamilyControls
import DeviceActivity
import ManagedSettings
import UserNotifications

// Bridge between the game (index.html) and Apple's Screen Time API.
// Only "the day's total passed N minutes" comes back; never which apps were used.
@objc(ScreenTimePlugin)
public class ScreenTimePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ScreenTimePlugin"
    public let jsName = "ScreenTime"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "status", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "authorize", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pickApps", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "minutesFor", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkLog", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "quickTest", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "resync", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "remindOn", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "remindOff", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "env", returnType: CAPPluginReturnPromise)
    ]

    static let group = "group.io.github.gamesbyvidal.lifetime"
    static let selectionKey = "selection"
    static let stepMinutes = 5
    static let maxMinutes = 16 * 60

    private var defaults: UserDefaults? { UserDefaults(suiteName: Self.group) }

    @objc func status(_ call: CAPPluginCall) {
        Self.purgeOld(defaults)
        let picked = defaults?.data(forKey: Self.selectionKey) != nil
        // authorizationStatus reads "not determined" for a moment after launch, then loads the real value. Wait up to 3 seconds for it.
        Task { @MainActor in
            var s = AuthorizationCenter.shared.authorizationStatus
            var tries = 0
            while s == .notDetermined && tries < 15 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                s = AuthorizationCenter.shared.authorizationStatus
                tries += 1
            }
            let state = s == .approved ? "approved" : s == .denied ? "denied" : "notDetermined"
            call.resolve(["authorized": s == .approved, "state": state, "picked": picked])
        }
    }

    // Apple's permission prompt has to be asked for on the main thread, or it never appears.
    @objc func authorize(_ call: CAPPluginCall) {
        Task { @MainActor in
            if AuthorizationCenter.shared.authorizationStatus == .approved { call.resolve(["authorized": true]); return }
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                call.resolve(["authorized": true])
            } catch {
                call.resolve(["authorized": false, "error": error.localizedDescription])
            }
        }
    }

    @objc func pickApps(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            // includeEntireCategory: a picked category also covers its websites and apps added later (Safari browsing was being missed).
            var saved = FamilyActivitySelection(includeEntireCategory: true)
            if self.defaults?.bool(forKey: "entireCategory") == true, let data = self.defaults?.data(forKey: Self.selectionKey),
               let old = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) { saved = old }
            let picker = PickerView(selection: saved) { picked in
                self.bridge?.viewController?.dismiss(animated: true)
                guard let picked = picked else { call.resolve(["picked": false]); return }
                if let data = try? JSONEncoder().encode(picked) { self.defaults?.set(data, forKey: Self.selectionKey) }
                self.defaults?.set(true, forKey: "entireCategory")
                call.resolve(["picked": true])
            }
            self.bridge?.viewController?.present(UIHostingController(rootView: picker), animated: true)
        }
    }

    // Watches the whole day (midnight to midnight, repeating) with one event per 5 minutes (192 events, up to 16 hours).
    // On iOS 17.4+ each event also counts what was used earlier today (includesPastActivity), so a restart never loses minutes.
    static func startMonitor(_ d: UserDefaults?, reason: String) throws {
        guard let data = d?.data(forKey: selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            throw NSError(domain: "Blip", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pick apps first"])
        }
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true)
        // The counter watches the picked categories and apps (pick All, then search for Safari and add it: Safari is in no category).
        // Websites are left out on purpose: Safari's own time already covers them, and counting both double counts.
        // History: picked categories + websites missed Safari (Nov 6: 1h vs iPhone 2h21m). An event with no filter
        // ("all activity", build 21) counted idle time (Nov 8: 12h30m vs 1h10m), so it is only watched for the log now.
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for m in stride(from: stepMinutes, through: maxMinutes, by: stepMinutes) {
            let name = DeviceActivityEvent.Name("m\(m)")
            if #available(iOS 17.4, *) {
                events[name] = DeviceActivityEvent(applications: selection.applicationTokens, categories: selection.categoryTokens, webDomains: [], threshold: DateComponents(minute: m), includesPastActivity: true)
            } else {
                events[name] = DeviceActivityEvent(applications: selection.applicationTokens, categories: selection.categoryTokens, webDomains: [], threshold: DateComponents(minute: m))
            }
        }
        // One time after build 21: today's stored total came from the no-filter counter (idle time included), so start today
        // over. The restart below makes iOS re-send today's real steps (includesPastActivity).
        if d?.bool(forKey: "reset-b22") != true {
            let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
            let day = f.string(from: Date())
            d?.removeObject(forKey: "minutes-" + day); d?.removeObject(forKey: "diag-" + day)
            d?.set(true, forKey: "reset-b22")
            log(d, "today's total reset (build 21 counted idle time)")
        }
        let center = DeviceActivityCenter()
        center.stopMonitoring([.daily])
        try center.startMonitoring(.daily, during: schedule, events: events)
        log(d, "counter started, picked categories + apps (" + reason + ")")
        // The old per-category watcher ("cats") is retired: the "picked", "web" and "apps" watchers below replace it.
        center.stopMonitoring([DeviceActivityName("cats"), DeviceActivityName("apps")])
        // TestFlight check: three watchers that are logged only, never counted: websites only, the build 20 counter
        // (categories + apps + websites) and the build 21 counter (no filter).
        func part(_ name: String, apps: Set<ApplicationToken> = [], cats: Set<ActivityCategoryToken> = [], webs: Set<WebDomainToken> = [], all: Bool = false, upTo: Int = 240) {
            guard all || !apps.isEmpty || !cats.isEmpty || !webs.isEmpty else { return }
            var ev: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
            for m in stride(from: Self.stepMinutes, through: upTo, by: Self.stepMinutes) {
                let n = DeviceActivityEvent.Name("\(name)\(m)")
                if #available(iOS 17.4, *) {
                    ev[n] = DeviceActivityEvent(applications: apps, categories: cats, webDomains: webs, threshold: DateComponents(minute: m), includesPastActivity: true)
                } else {
                    ev[n] = DeviceActivityEvent(applications: apps, categories: cats, webDomains: webs, threshold: DateComponents(minute: m))
                }
            }
            let a = DeviceActivityName(name)
            center.stopMonitoring([a])
            do { try center.startMonitoring(a, during: schedule, events: ev) }
            catch { Self.log(d, name + " watcher failed: " + error.localizedDescription) }
        }
        part("web", webs: selection.webDomainTokens)
        // The build 20 way (picked apps, categories and websites) and the build 21 way (no filter), side by side.
        part("picked", apps: selection.applicationTokens, cats: selection.categoryTokens, webs: selection.webDomainTokens, upTo: 480)
        part("all", all: true, upTo: 480)
        log(d, d?.bool(forKey: "entireCategory") == true ? "whole categories incl. websites: on" : "whole categories incl. websites: OFF (re-pick in Change what counts)")
    }

    @objc func start(_ call: CAPPluginCall) {
        do {
            try Self.startMonitor(defaults, reason: "connect or change what counts")
            call.resolve(["started": true])
        } catch {
            call.reject("Could not start: \(error.localizedDescription)")
        }
    }

    // Called each time the app opens. On iOS 17.4+ restarting with includesPastActivity makes iOS re-check today's
    // full total and re-send any 5-minute steps it missed. Older iOS would lose earlier minutes on a restart, so it skips.
    @objc func resync(_ call: CAPPluginCall) {
        guard #available(iOS 17.4, *) else { call.resolve(["resynced": false]); return }
        guard AuthorizationCenter.shared.authorizationStatus == .approved else { call.resolve(["resynced": false]); return }
        do {
            try Self.startMonitor(defaults, reason: "app opened, re-sync")
            call.resolve(["resynced": true])
        } catch {
            Self.log(defaults, "re-sync failed: " + error.localizedDescription)
            call.resolve(["resynced": false])
        }
    }

    // day: "YYYY-MM-DD" in the phone's time zone. Returns the highest 5-minute step reached, or null.
    @objc func minutesFor(_ call: CAPPluginCall) {
        let day = call.getString("day") ?? ""
        defaults?.synchronize() // pick up steps the background counter just wrote
        if let m = defaults?.object(forKey: "minutes-" + day) as? Int { call.resolve(["minutes": m]) }
        else { call.resolve(["minutes": NSNull()]) }
    }

    // TestFlight "Screen Time check": the day's log of when each 5-minute step arrived, plus what is being counted.
    static func log(_ d: UserDefaults?, _ what: String) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let t = DateFormatter(); t.locale = Locale(identifier: "en_US_POSIX"); t.dateFormat = "HH:mm"
        let key = "log-" + f.string(from: Date())
        var list = d?.stringArray(forKey: key) ?? []
        list.append(t.string(from: Date()) + " " + what)
        d?.set(list, forKey: key)
    }
    @objc func checkLog(_ call: CAPPluginCall) {
        let day = call.getString("day") ?? ""
        var apps = 0, cats = 0, webs = 0
        if let data = defaults?.data(forKey: Self.selectionKey), let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            apps = sel.applicationTokens.count; cats = sel.categoryTokens.count; webs = sel.webDomainTokens.count
        }
        let acts = DeviceActivityCenter().activities.map { $0.rawValue }
        call.resolve(["log": defaults?.stringArray(forKey: "log-" + day) ?? [], "apps": apps, "categories": cats, "webDomains": webs, "watching": acts,
                      "diag": defaults?.dictionary(forKey: "diag-" + day) ?? [:],
                      "qt": defaults?.dictionary(forKey: "qt-best") ?? [:], "qtStart": defaults?.double(forKey: "qt-start") ?? 0])
    }

    // TestFlight quick test: four counting methods side by side from this moment for one hour, in 1-minute steps,
    // counting only use AFTER the tap (includesPastActivity false). Lets us compare against iPhone Screen Time many times a day.
    // Logged only, never counted toward the Blip.
    static let qtNames = ["qt-counter", "qt-web", "qt-all", "qt-cats"]
    @objc func quickTest(_ call: CAPPluginCall) {
        guard let d = defaults, let data = d.data(forKey: Self.selectionKey),
              let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { call.reject("Pick apps first"); return }
        let cal = Calendar.current, now = Date()
        let startDate = now.addingTimeInterval(-120)
        var endDate = now.addingTimeInterval(3600)
        if !cal.isDate(endDate, inSameDayAs: now) { endDate = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? endDate }
        if endDate.timeIntervalSince(startDate) < 16 * 60 { call.reject("Too close to midnight. Try after 12:05 AM."); return }
        let comps: (Date) -> DateComponents = { cal.dateComponents([.hour, .minute, .second], from: $0) }
        let schedule = DeviceActivitySchedule(intervalStart: comps(startDate), intervalEnd: comps(endDate), repeats: false)
        let center = DeviceActivityCenter()
        center.stopMonitoring(Self.qtNames.map { DeviceActivityName($0) })
        d.removeObject(forKey: "qt-best")
        d.set(now.timeIntervalSince1970, forKey: "qt-start")
        let sets: [(String, Set<ApplicationToken>, Set<ActivityCategoryToken>, Set<WebDomainToken>)] = [
            ("qt-counter", sel.applicationTokens, sel.categoryTokens, []),        // the real counter (categories + apps incl. Safari)
            ("qt-web", sel.applicationTokens, sel.categoryTokens, sel.webDomainTokens), // build 20 way (with websites)
            ("qt-all", [], [], []),                                               // build 21 way (no filter)
            ("qt-cats", [], sel.categoryTokens, [])                               // categories only (without Safari and other picked apps)
        ]
        var failed: [String] = []
        for (name, apps, cats, webs) in sets {
            var ev: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
            for m in 1...60 {
                let n = DeviceActivityEvent.Name("t\(m)")
                if #available(iOS 17.4, *) {
                    ev[n] = DeviceActivityEvent(applications: apps, categories: cats, webDomains: webs, threshold: DateComponents(minute: m), includesPastActivity: false)
                } else {
                    ev[n] = DeviceActivityEvent(applications: apps, categories: cats, webDomains: webs, threshold: DateComponents(minute: m))
                }
            }
            do { try center.startMonitoring(DeviceActivityName(name), during: schedule, events: ev) }
            catch { failed.append(name + ": " + error.localizedDescription) }
        }
        Self.log(d, "quick test started" + (failed.isEmpty ? "" : " (failed: " + failed.joined(separator: "; ") + ")"))
        call.resolve(["started": failed.count < sets.count, "failed": failed])
    }

    // Daily totals are only kept for about a week (privacy policy). Keys look like "minutes-YYYY-MM-DD".
    static let keepDays = 8
    static func purgeOld(_ d: UserDefaults?) {
        guard let d = d else { return }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date()) else { return }
        let oldest = f.string(from: cutoff)
        for key in d.dictionaryRepresentation().keys {
            if key.hasPrefix("minutes-"), String(key.dropFirst(8)) < oldest { d.removeObject(forKey: key) }
            if key.hasPrefix("log-"), String(key.dropFirst(4)) < oldest { d.removeObject(forKey: key) }
            if key.hasPrefix("diag-"), String(key.dropFirst(5)) < oldest { d.removeObject(forKey: key) }
        }
    }

    // Optional morning reminder, off until the player turns it on in Settings (the permission prompt shows only then).
    // One a day, and it only says the next year is ready: never results, minutes, streaks or the shop.
    static let reminderID = "blip-morning"
    @objc func remindOn(_ call: CAPPluginCall) {
        let name = call.getString("name") ?? "Your Blip"
        let hour = call.getInt("hour") ?? 8, minute = call.getInt("minute") ?? 0
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { call.resolve(["granted": false]); return }
            let content = UNMutableNotificationContent()
            content.body = "\(name)'s next year is ready"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
            center.removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
            center.add(UNNotificationRequest(identifier: Self.reminderID, content: content, trigger: trigger)) { err in
                call.resolve(["granted": err == nil])
            }
        }
    }
    // TestFlight builds have a sandbox receipt; App Store builds don't. Testing tools only show in TestFlight.
    @objc func env(_ call: CAPPluginCall) {
        call.resolve(["testflight": Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"])
    }
    @objc func remindOff(_ call: CAPPluginCall) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
        call.resolve()
    }
}

extension DeviceActivityName { static let daily = Self("daily") }

private struct PickerView: View {
    @State var selection: FamilyActivitySelection
    let done: (FamilyActivitySelection?) -> Void
    var body: some View {
        NavigationView {
            FamilyActivityPicker(selection: $selection)
                .navigationTitle("Tick All, then search Safari")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { done(nil) } }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { done(selection) } }
                }
        }
    }
}
