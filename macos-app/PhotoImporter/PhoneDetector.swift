import Foundation
import ImageCaptureCore

struct DetectedPhone: Identifiable, Equatable {
    // Name as reported by ImageCaptureCore; the importer matches it with --device.
    let name: String
    let serial: String?
    var id: String { serial ?? name }
}

// Lists cameras (iPhones) currently visible to ImageCaptureCore. Stopped while an import runs
// so it never competes with the importer's own browser.
@MainActor
final class PhoneDetector: NSObject, ObservableObject, @preconcurrency ICDeviceBrowserDelegate {
    @Published private(set) var phones: [DetectedPhone] = []
    private let browser = ICDeviceBrowser()
    private var devices: [ICCameraDevice] = []

    override init() {
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(
            rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue)!
    }

    func start() { browser.start() }

    func stop() {
        browser.stop()
        devices = []
        phones = []
    }

    func isConnected(name: String) -> Bool { phones.contains { $0.name == name } }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        devices.append(camera)
        refresh()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        devices.removeAll { $0 === device }
        refresh()
    }

    private func refresh() {
        phones = devices.compactMap { camera in
            camera.name.map { DetectedPhone(name: $0, serial: camera.serialNumberString) }
        }
    }
}
