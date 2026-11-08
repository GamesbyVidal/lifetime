import DeviceActivity
import Foundation

// Runs in the background, separately from the app. iOS calls eventDidReachThreshold each
// time the day's total screen time passes another 5 minutes ("m5", "m10", ...).
// We keep only the highest step for the day, in the shared App Group, on this phone.
class MonitorExtension: DeviceActivityMonitor {
    let defaults = UserDefaults(suiteName: "group.io.github.gamesbyvidal.lifetime")

    private func today() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // TestFlight "Screen Time check": when each step arrived, kept on this phone with the daily totals (same 8-day purge).
    private func log(_ what: String) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        let key = "log-" + today()
        var list = defaults?.stringArray(forKey: key) ?? []
        list.append(f.string(from: Date()) + " " + what)
        if list.count > 1500 { list.removeFirst(list.count - 1500) }
        defaults?.set(list, forKey: key)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        log(activity.rawValue + " end")
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        log(activity.rawValue + " start")
        let key = "minutes-" + today()
        if defaults?.object(forKey: key) == nil { defaults?.set(0, forKey: key) }
        purgeOld()
    }

    // Keep about a week of daily totals (same rule as ScreenTimePlugin.purgeOld).
    private func purgeOld() {
        guard let d = defaults, let cutoff = Calendar.current.date(byAdding: .day, value: -8, to: Date()) else { return }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let oldest = f.string(from: cutoff)
        for key in d.dictionaryRepresentation().keys {
            if key.hasPrefix("minutes-"), String(key.dropFirst(8)) < oldest { d.removeObject(forKey: key) }
            if key.hasPrefix("log-"), String(key.dropFirst(4)) < oldest { d.removeObject(forKey: key) }
            if key.hasPrefix("diag-"), String(key.dropFirst(5)) < oldest { d.removeObject(forKey: key) }
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        // TestFlight check: per-category steps ("c3_45" = category #3 passed 45 minutes). Logged only, never counted.
        if activity == DeviceActivityName("cats") { log("cat " + event.rawValue.dropFirst().replacingOccurrences(of: "_", with: ": ") + "m"); return }
        // TestFlight check: websites-only ("web45"), build 20 way ("picked45") and no-filter ("all45") watchers. Logged only, never counted.
        // TestFlight quick test ("qt-..." activities, "t7" = 7 minutes since the test started). New highs only.
        if activity.rawValue.hasPrefix("qt-") {
            guard let m = Int(event.rawValue.dropFirst()) else { return }
            let name = String(activity.rawValue.dropFirst(3))
            var best = defaults?.dictionary(forKey: "qt-best") as? [String: Int] ?? [:]
            if m > (best[name] ?? 0) { best[name] = m; defaults?.set(best, forKey: "qt-best"); log("test " + name + " \(m)m") }
            return
        }
        // Only new highs are logged: every app open makes iOS re-send all of today's steps, which flooded the log.
        if ["web", "apps", "picked", "all"].contains(activity.rawValue) {
            guard let m = Int(event.rawValue.drop(while: { $0.isLetter })) else { return }
            let key = "diag-" + today()
            var best = defaults?.dictionary(forKey: key) as? [String: Int] ?? [:]
            if m > (best[activity.rawValue] ?? 0) { best[activity.rawValue] = m; defaults?.set(best, forKey: key); log(activity.rawValue + " \(m)m") }
            return
        }
        guard let m = Int(event.rawValue.dropFirst()) else { return }
        // iOS 26 sometimes fires steps that can't be real yet (developer forums). A day can't hold more minutes than have passed since midnight.
        let sinceMidnight = Int(Date().timeIntervalSince(Calendar.current.startOfDay(for: Date())) / 60)
        if m > sinceMidnight + 1 { log("\(m)m ignored (too early)"); return }
        let key = "minutes-" + today()
        if m > (defaults?.integer(forKey: key) ?? 0) { defaults?.set(m, forKey: key); log("\(m)m") }
    }
}
