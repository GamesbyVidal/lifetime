import UIKit
import Capacitor

// The app's web view. Registers the plugins that live in this app (not from npm).
class MainViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(StorePlugin())
    }
}
