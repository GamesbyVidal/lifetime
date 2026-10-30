import Foundation
import Capacitor
import SwiftUI
import FamilyControls
import DeviceActivity

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
        CAPPluginMethod(name: "minutesFor", returnType: CAPPluginReturnPromise)
    ]

    static let group = "group.io.github.gamesbyvidal.lifetime"
    static let selectionKey = "selection"
    static let stepMinutes = 15
    static let maxMinutes = 16 * 60

    private var defaults: UserDefaults? { UserDefaults(suiteName: Self.group) }

    @objc func status(_ call: CAPPluginCall) {
        let s = AuthorizationCenter.shared.authorizationStatus
        call.resolve(["authorized": s == .approved, "picked": defaults?.data(forKey: Self.selectionKey) != nil])
    }

    @objc func authorize(_ call: CAPPluginCall) {
        Task {
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
            var saved = FamilyActivitySelection()
            if let data = self.defaults?.data(forKey: Self.selectionKey),
               let old = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) { saved = old }
            let picker = PickerView(selection: saved) { picked in
                self.bridge?.viewController?.dismiss(animated: true)
                guard let picked = picked else { call.resolve(["picked": false]); return }
                if let data = try? JSONEncoder().encode(picked) { self.defaults?.set(data, forKey: Self.selectionKey) }
                call.resolve(["picked": true])
            }
            self.bridge?.viewController?.present(UIHostingController(rootView: picker), animated: true)
        }
    }

    // Watches the whole day (midnight to midnight, repeating) with one event per 15 minutes.
    @objc func start(_ call: CAPPluginCall) {
        guard let data = defaults?.data(forKey: Self.selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            call.reject("Pick apps first"); return
        }
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true)
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for m in stride(from: Self.stepMinutes, through: Self.maxMinutes, by: Self.stepMinutes) {
            events[DeviceActivityEvent.Name("m\(m)")] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: m))
        }
        do {
            let center = DeviceActivityCenter()
            center.stopMonitoring([.daily])
            try center.startMonitoring(.daily, during: schedule, events: events)
            call.resolve(["started": true])
        } catch {
            call.reject("Could not start: \(error.localizedDescription)")
        }
    }

    // day: "YYYY-MM-DD" in the phone's time zone. Returns the highest 15-minute step reached, or null.
    @objc func minutesFor(_ call: CAPPluginCall) {
        let day = call.getString("day") ?? ""
        if let m = defaults?.object(forKey: "minutes-" + day) as? Int { call.resolve(["minutes": m]) }
        else { call.resolve(["minutes": NSNull()]) }
    }
}

extension DeviceActivityName { static let daily = Self("daily") }

private struct PickerView: View {
    @State var selection: FamilyActivitySelection
    let done: (FamilyActivitySelection?) -> Void
    var body: some View {
        NavigationView {
            FamilyActivityPicker(selection: $selection)
                .navigationTitle("Choose All apps")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { done(nil) } }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { done(selection) } }
                }
        }
    }
}
