import DeviceActivity
import SwiftUI

// Apple's Screen Time report view. iOS runs this in a locked-down sandbox and draws its view inside Blip,
// so the Today screen can show the exact time so far, the same number as Settings > Screen Time.
// The number never leaves this extension: no network, no App Group writes, nothing goes back to the app
// (Lawyer conditions, Nov 6 and Nov 8). Day total only, never a per-app list.
@main
struct BlipReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TotalScene { total in TotalView(total: total) }
    }
}

extension DeviceActivityReport.Context {
    static let total = Self("total")
}

struct TotalScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .total
    let content: (TimeInterval) -> TotalView

    // Adds up today's activity on this iPhone (the filter comes from the app: today, this device).
    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TimeInterval {
        var total: TimeInterval = 0
        for await d in data {
            for await segment in d.activitySegments { total += segment.totalActivityDuration }
        }
        return total
    }
}

struct TotalView: View {
    let total: TimeInterval
    var text: String {
        let m = Int(total / 60), h = m / 60, mm = m % 60
        return h > 0 ? (mm > 0 ? "\(h)h \(mm)m" : "\(h)h") : "\(mm)m"
    }
    var body: some View {
        // Matches the web card: white background, dark bold rounded number, left aligned.
        HStack(spacing: 0) {
            Text(text)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(Color(red: 0.17, green: 0.13, blue: 0.27))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}
