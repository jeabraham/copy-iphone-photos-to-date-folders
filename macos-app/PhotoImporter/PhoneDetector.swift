import Foundation
import ImageCaptureCore

struct DetectedPhone: Identifiable, Equatable {
    // Name as reported by ImageCaptureCore; the importer matches it with --device.
    let name: String
    let serial: String?
    var id: String { serial ?? name }
}

// Keeps one discovery browser alive and forwards devices to the active importer.
// Importing must not discard a phone that this browser has already discovered.
@MainActor
final class PhoneDetector: NSObject, ObservableObject, @preconcurrency ICDeviceBrowserDelegate {
    @Published private(set) var phones: [DetectedPhone] = []
    private let browser = ICDeviceBrowser()
    private var devices: [ICCameraDevice] = []
    private weak var activeImporter: Importer?

    override init() {
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(
            rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue)!
    }

    func start() {
        guard !browser.isBrowsing else { return }
        devices = []
        phones = []
        browser.start()
    }

    func beginImport(_ importer: Importer) {
        activeImporter = importer
        importer.resetWatchdog()
        start()
        // Existing devices won't necessarily produce another didAdd callback.
        for camera in devices {
            importer.deviceBrowser(browser, didAdd: camera, moreComing: false)
        }
    }

    func endImport() {
        activeImporter = nil
    }

    func isConnected(name: String) -> Bool { phones.contains { $0.name == name } }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        if !devices.contains(where: { $0 === camera }) {
            devices.append(camera)
        }
        refresh()
        activeImporter?.deviceBrowser(browser, didAdd: camera, moreComing: moreComing)
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        devices.removeAll { $0 === device }
        refresh()
        activeImporter?.deviceBrowser(browser, didRemove: device, moreGoing: moreGoing)
    }

    private func refresh() {
        phones = devices.compactMap { camera in
            camera.name.map { DetectedPhone(name: $0, serial: camera.serialNumberString) }
        }
    }
}
