import DeviceActivity
import Foundation

// Runs in the background, separately from the app. iOS calls eventDidReachThreshold each
// time the day's total screen time passes another 15 minutes ("m15", "m30", ...).
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

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        let key = "minutes-" + today()
        if defaults?.object(forKey: key) == nil { defaults?.set(0, forKey: key) }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let m = Int(event.rawValue.dropFirst()) else { return }
        let key = "minutes-" + today()
        if m > (defaults?.integer(forKey: key) ?? 0) { defaults?.set(m, forKey: key) }
    }
}
