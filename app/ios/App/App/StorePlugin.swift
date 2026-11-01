import Foundation
import Capacitor
import StoreKit

// Gift shop purchases through Apple (StoreKit 2). The game (index.html) calls it as
// Capacitor.registerPlugin('BlipStore'). Items are one-time purchases; Blip Club is a subscription.
@objc(StorePlugin)
public class StorePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "StorePlugin"
    public let jsName = "BlipStore"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "products", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "buy", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "owned", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "restore", returnType: CAPPluginReturnPromise)
    ]

    private var updates: Task<Void, Never>?

    override public func load() {
        // Purchases that finish later (Ask to Buy, renewals, a buy on another device) arrive here.
        updates = Task {
            for await result in Transaction.updates {
                if case .verified(let t) = result {
                    await t.finish()
                    self.notifyListeners("changed", data: ["id": t.productID, "owned": t.revocationDate == nil])
                }
            }
        }
    }

    deinit { updates?.cancel() }

    // Prices come from Apple so they show in the player's own currency.
    @objc func products(_ call: CAPPluginCall) {
        let ids = call.getArray("ids", String.self) ?? []
        Task {
            do {
                let list = try await Product.products(for: ids)
                call.resolve(["products": list.map { ["id": $0.id, "price": $0.displayPrice, "name": $0.displayName] }])
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func buy(_ call: CAPPluginCall) {
        guard let id = call.getString("id") else { call.reject("No product id"); return }
        Task {
            do {
                guard let product = try await Product.products(for: [id]).first else { call.reject("Not for sale yet"); return }
                switch try await product.purchase() {
                case .success(let result):
                    guard case .verified(let t) = result else { call.resolve(["status": "failed"]); return }
                    await t.finish()
                    call.resolve(["status": "bought", "id": t.productID])
                case .pending:
                    call.resolve(["status": "pending"])
                case .userCancelled:
                    call.resolve(["status": "cancelled"])
                @unknown default:
                    call.resolve(["status": "failed"])
                }
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    // Everything this Apple ID owns right now (one-time items plus an active Club subscription).
    @objc func owned(_ call: CAPPluginCall) {
        Task { call.resolve(["ids": await Self.entitlements()]) }
    }

    // "Restore purchases" button: asks Apple to re-sync, then reports what's owned.
    @objc func restore(_ call: CAPPluginCall) {
        Task {
            try? await AppStore.sync()
            call.resolve(["ids": await Self.entitlements()])
        }
    }

    static func entitlements() async -> [String] {
        var ids: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil { ids.append(t.productID) }
        }
        return ids
    }
}
