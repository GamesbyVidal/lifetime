import WidgetKit
import SwiftUI

// Blip's home screen and lock screen widgets (Matthew's picks, 2026-11-13; Lawyer conditions applied):
//  - shows only Blip's own count for today (the 5-minute steps the monitor saved on this phone), the goal and the player's Blip
//  - reads the shared App Group on this phone; no network, no analytics, nothing shared
//  - count, left/over, bar, mood and streak are privacy-sensitive (hidden when the phone hides widget data while locked)
//  - "Blip's count", "about ... left" and "as of" wording; never claims to match iPhone's Settings
//  - tapping opens the app (Today); never the shop
//  - kept off the Mac desktop (iPhone widgets on Mac)

private let group = "group.io.github.gamesbyvidal.lifetime"
private let ink = Color(red: 0.231, green: 0.165, blue: 0.290)      // #3b2a4a outline
private let purple = Color(red: 0.486, green: 0.361, blue: 1.0)     // #7c5cff
private let sunset = Color(red: 1.0, green: 0.478, blue: 0.349)     // #ff7a59
private let cream = Color(red: 1.0, green: 0.980, blue: 0.941)      // #fffaf0
private let soft = Color(red: 0.42, green: 0.36, blue: 0.48)

struct BlipEntry: TimelineEntry {
    let date: Date
    let ready: Bool
    let minutes: Int
    let goal: Int
    let name: String
    let age: Int
    let streak: Int
    let skin: Color
    let hair: Color
    let girl: Bool

    var over: Bool { minutes > goal }
    var progress: Double { goal > 0 ? min(1, Double(minutes) / Double(goal)) : 0 }
    var tint: Color { over ? sunset : purple }
    var leftText: String { over ? fmt(minutes - goal) + " over" : "about " + fmt(goal - minutes) + " left" }
    var shortLeft: String { over ? fmt(minutes - goal) + " over" : fmt(goal - minutes) + " left" }
    var asOf: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.timeStyle = .short
        f.dateStyle = .none
        return "updated " + f.string(from: date)
    }

    static let sample = BlipEntry(date: Date(), ready: true, minutes: 95, goal: 120, name: "Pip", age: 24, streak: 3,
                                  skin: Color(hex: "#f1c27d"), hair: Color(hex: "#3b2a4a"), girl: false)
}

func fmt(_ m: Int) -> String {
    let h = m / 60, mm = m % 60
    if h == 0 { return "\(mm)m" }
    return mm == 0 ? "\(h)h" : "\(h)h \(mm)m"
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

struct Provider: TimelineProvider {
    private func day(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    func entry(at date: Date) -> BlipEntry {
        let d = UserDefaults(suiteName: group)
        guard let info = d?.dictionary(forKey: "widget"), let goal = info["goal"] as? Int else {
            return BlipEntry(date: date, ready: false, minutes: 0, goal: 0, name: "", age: 0, streak: 0,
                             skin: Color(hex: "#f1c27d"), hair: ink, girl: false)
        }
        let minutes = d?.integer(forKey: "minutes-" + day(date)) ?? 0
        return BlipEntry(date: date, ready: true, minutes: minutes, goal: goal,
                         name: info["name"] as? String ?? "", age: info["age"] as? Int ?? 0, streak: info["streak"] as? Int ?? 0,
                         skin: Color(hex: info["skin"] as? String ?? "#f1c27d"), hair: Color(hex: info["hair"] as? String ?? "#3b2a4a"),
                         girl: info["girl"] as? Bool ?? false)
    }

    func placeholder(in context: Context) -> BlipEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (BlipEntry) -> Void) {
        let e = entry(at: Date())
        completion(context.isPreview && !e.ready ? .sample : e)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BlipEntry>) -> Void) {
        let now = Date()
        var entries = [entry(at: now)]
        // A fresh day starts at 0 at midnight even if nothing wakes the widget.
        if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)),
           midnight.timeIntervalSince(now) < 15 * 60 {
            entries.append(entry(at: midnight))
        }
        // The monitor asks for a reload on every new 5-minute step; this is the fallback.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

// MARK: - The player's own Blip (pictures the app draws with its own art; simple drawing only as a fallback)

func blipArt(_ name: String) -> UIImage? {
    guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
    return UIImage(contentsOfFile: dir.appendingPathComponent("widget-" + name + ".png").path)
}

struct Mouth: Shape {
    let mood: Int // 1 smile, 0 neutral, -1 glum
    func path(in r: CGRect) -> Path {
        var p = Path()
        let y = r.minY + r.height * 0.70
        switch mood {
        case 1:
            p.move(to: CGPoint(x: r.minX + r.width * 0.37, y: y))
            p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.63, y: y), control: CGPoint(x: r.midX, y: y + r.height * 0.13))
        case -1:
            p.move(to: CGPoint(x: r.minX + r.width * 0.40, y: y + r.height * 0.06))
            p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.60, y: y + r.height * 0.06), control: CGPoint(x: r.midX, y: y - r.height * 0.03))
        default:
            p.move(to: CGPoint(x: r.minX + r.width * 0.41, y: y + r.height * 0.03))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.59, y: y + r.height * 0.03))
        }
        return p
    }
}

struct BlipFace: View {
    let e: BlipEntry
    var mono = false
    @Environment(\.redactionReasons) private var reasons

    var body: some View {
        // The mood gives the result away, so it goes neutral when the phone hides private widget data.
        let art = blipArt(reasons.contains(.privacy) ? "faceNeutral" : (e.over ? "faceGlum" : "faceHappy"))
        if let art = art {
            Image(uiImage: art).resizable().scaledToFit().clipShape(Circle())
        } else {
            drawn
        }
    }

    private var drawn: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let line = max(1.5, s * 0.05)
            // The mood gives the result away, so it goes neutral when the phone hides private widget data.
            let mood = reasons.contains(.privacy) ? 0 : (e.over ? -1 : 1)
            let hairC = mono ? Color.primary : e.hair
            let skinC = mono ? Color.primary.opacity(0.25) : e.skin
            ZStack {
                if e.girl {
                    RoundedRectangle(cornerRadius: s * 0.3)
                        .fill(hairC)
                        .frame(width: s * 0.96, height: s * 0.95)
                        .offset(y: s * 0.12)
                }
                Circle().fill(skinC)
                Circle()
                    .fill(hairC)
                    .frame(width: s * 1.05, height: s * 0.9)
                    .offset(y: -s * (e.girl ? 0.42 : 0.47))
                    .mask(Circle())
                Circle().stroke(mono ? Color.primary : ink, lineWidth: line)
                HStack(spacing: s * 0.2) {
                    Capsule().fill(mono ? Color.primary : ink).frame(width: s * 0.09, height: s * 0.13)
                    Capsule().fill(mono ? Color.primary : ink).frame(width: s * 0.09, height: s * 0.13)
                }
                .offset(y: s * 0.04)
                if !mono {
                    HStack(spacing: s * 0.42) {
                        Circle().fill(Color.pink.opacity(0.35)).frame(width: s * 0.12)
                        Circle().fill(Color.pink.opacity(0.35)).frame(width: s * 0.12)
                    }
                    .offset(y: s * 0.17)
                }
                Mouth(mood: mood)
                    .stroke(mono ? Color.primary : ink, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .privacySensitive()
            }
            .frame(width: s, height: s)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
    }
}

// MARK: - Home screen: small ring

struct SmallView: View {
    let e: BlipEntry
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(e.tint.opacity(0.18), lineWidth: 9)
                Circle().trim(from: 0, to: e.progress)
                    .stroke(e.tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .privacySensitive()
                BlipFace(e: e).padding(12)
            }
            .frame(width: 84, height: 84)
            Text(fmt(e.minutes)).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundColor(ink).privacySensitive()
            Text(e.shortLeft).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(e.over ? sunset : Color(red: 0.2, green: 0.6, blue: 0.3)).privacySensitive()
            Text(e.asOf).font(.system(size: 9, design: .rounded)).foregroundColor(soft)
        }
    }
}

// MARK: - Home screen: medium room

struct RoomView: View {
    let e: BlipEntry
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(red: 1.0, green: 0.86, blue: 0.68))
                Rectangle().fill(Color(red: 0.86, green: 0.62, blue: 0.42)).frame(height: h * 0.2).offset(y: h * 0.8)
                // window
                RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.75, green: 0.88, blue: 1.0))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(ink, lineWidth: 2))
                    .frame(width: w * 0.28, height: h * 0.26).offset(x: w * 0.08, y: h * 0.08)
                // picture
                RoundedRectangle(cornerRadius: 3).fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(ink, lineWidth: 2))
                    .frame(width: w * 0.2, height: h * 0.16).offset(x: w * 0.62, y: h * 0.1)
                // rug
                Ellipse().fill(Color(red: 1.0, green: 0.56, blue: 0.69))
                    .overlay(Ellipse().stroke(ink, lineWidth: 2))
                    .frame(width: w * 0.7, height: h * 0.12).offset(x: w * 0.15, y: h * 0.82)
                // the Blip
                if let whole = blipArt(e.over ? "bodyGlum" : "bodyHappy") {
                    Image(uiImage: whole).resizable().scaledToFit()
                        .frame(width: w * 0.7, height: h * 0.84)
                        .frame(width: w).offset(y: h * 0.1)
                        .privacySensitive()
                } else {
                VStack(spacing: -h * 0.03) {
                    BlipFace(e: e).frame(width: w * 0.42, height: w * 0.42)
                    RoundedRectangle(cornerRadius: 8).fill(e.girl ? Color(red: 0.36, green: 0.76, blue: 0.69) : Color(red: 0.22, green: 0.62, blue: 0.56))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ink, lineWidth: 2))
                        .frame(width: w * 0.3, height: h * 0.26)
                }
                .frame(width: w).offset(y: h * 0.3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ink, lineWidth: 2.5))
        }
    }
}

struct MediumView: View {
    let e: BlipEntry
    var body: some View {
        HStack(spacing: 12) {
            RoomView(e: e).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                Text("Blip's count").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(soft)
                HStack(alignment: .firstTextBaseline) {
                    Text(fmt(e.minutes)).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundColor(ink).privacySensitive()
                    Spacer(minLength: 2)
                    Text(e.leftText).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(e.over ? sunset : Color(red: 0.2, green: 0.6, blue: 0.3)).privacySensitive()
                }
                ProgressView(value: e.progress).tint(e.tint).privacySensitive()
                HStack {
                    Text(e.asOf)
                    Spacer()
                    Text("goal " + fmt(e.goal))
                }
                .font(.system(size: 9, design: .rounded)).foregroundColor(soft)
                if e.streak > 0 {
                    Text("🔥 \(e.streak) day streak")
                        .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(ink)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .overlay(Capsule().stroke(ink, lineWidth: 1.5))
                        .privacySensitive()
                }
                Text("🎂 \(e.name) turns \(e.age + 1) tomorrow morning")
                    .font(.system(size: 10, design: .rounded)).foregroundColor(ink).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Lock screen: rectangle (one tint, drawn by iOS)

struct LockView: View {
    let e: BlipEntry
    var body: some View {
        HStack(spacing: 8) {
            BlipFace(e: e, mono: true).frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(fmt(e.minutes)).font(.system(size: 20, weight: .heavy, design: .rounded)).privacySensitive()
                ProgressView(value: e.progress).privacySensitive()
                Text(e.leftText).font(.system(size: 11, weight: .semibold, design: .rounded)).privacySensitive()
                Text(e.asOf).font(.system(size: 9, design: .rounded)).opacity(0.7)
            }
        }
    }
}

struct SetupView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Blip").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundColor(purple)
            Text("Open Blip once to show your count here.").font(.system(size: 11, design: .rounded)).foregroundColor(soft).multilineTextAlignment(.center)
        }
    }
}

struct BlipWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let e: BlipEntry
    var body: some View {
        Group {
            if !e.ready {
                SetupView()
            } else {
                switch family {
                case .systemMedium: MediumView(e: e)
                case .accessoryRectangular: LockView(e: e)
                default: SmallView(e: e)
                }
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryRectangular { Color.clear } else { cream }
        }
    }
}

@main
struct BlipWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BlipCount", provider: Provider()) { e in
            BlipWidgetView(e: e)
        }
        .configurationDisplayName("Blip's count")
        .description("Blip's count for today, your goal, and your Blip.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .disfavoredLocations([.iPhoneWidgetsOnMac], for: [.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
