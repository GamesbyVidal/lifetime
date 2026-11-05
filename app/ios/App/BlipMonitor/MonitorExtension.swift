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
        if list.count > 400 { list.removeFirst(list.count - 400) }
        defaults?.set(list, forKey: key)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        log("day end")
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        log("day start")
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
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let m = Int(event.rawValue.dropFirst()) else { return }
        log("\(m)m")
        let key = "minutes-" + today()
        if m > (defaults?.integer(forKey: key) ?? 0) { defaults?.set(m, forKey: key) }
    }
}
