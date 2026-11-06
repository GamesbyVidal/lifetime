import Foundation
import Capacitor
import UIKit

// "Save picture" on the Share sheet: puts the Blip picture straight into the Photos app.
// Add-only access (NSPhotoLibraryAddUsageDescription): the app can't see or read the player's photos.
@objc(PhotosPlugin)
public class PhotosPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "PhotosPlugin"
    public let jsName = "BlipPhotos"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "save", returnType: CAPPluginReturnPromise)
    ]

    private var pending: CAPPluginCall?

    // data = base64 PNG (with or without a "data:image/png;base64," prefix).
    @objc func save(_ call: CAPPluginCall) {
        guard var b64 = call.getString("data") else { call.reject("No picture"); return }
        if let comma = b64.firstIndex(of: ",") { b64 = String(b64[b64.index(after: comma)...]) }
        guard let data = Data(base64Encoded: b64), let image = UIImage(data: data) else { call.reject("Bad picture"); return }
        DispatchQueue.main.async {
            self.pending = call
            UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.done(_:didFinishSavingWithError:contextInfo:)), nil)
        }
    }

    @objc func done(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        guard let call = pending else { return }
        pending = nil
        if let error = error { call.reject(error.localizedDescription) } else { call.resolve(["saved": true]) }
    }
}
