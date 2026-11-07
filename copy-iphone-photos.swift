#!/usr/bin/env swift
import Foundation

#if os(macOS)
import ImageCaptureCore
import UniformTypeIdentifiers
#endif

struct ImportError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct Options {
    var destination = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var start: Date?
    var end: Date?
    var excludeMovies = false
    var overwrite = false
    var dryRun = false
    var deviceName: String?
    var timeout: TimeInterval = 120

    static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--exclude-movies": options.excludeMovies = true
            case "--overwrite": options.overwrite = true
            case "--dry-run": options.dryRun = true
            case "--dest", "--from", "--to", "--device", "--timeout":
                index += 1
                guard index < arguments.count, !arguments[index].hasPrefix("--"),
                      !arguments[index].isEmpty else {
                    throw ImportError(message: "Missing value for \(argument)")
                }
                let value = arguments[index]
                switch argument {
                case "--dest": options.destination = URL(fileURLWithPath: value).standardizedFileURL
                case "--device": options.deviceName = value
                case "--timeout":
                    guard let seconds = Double(value), seconds.isFinite, seconds > 0 else {
                        throw ImportError(message: "--timeout must be a positive number of seconds")
                    }
                    options.timeout = seconds
                default:
                    let formatter = dateFormatter()
                    guard let date = formatter.date(from: value),
                          formatter.string(from: date) == value else {
                        throw ImportError(message: "\(argument) requires a valid YYYY-MM-DD date")
                    }
                    if argument == "--from" {
                        options.start = date
                    } else {
                        var calendar = Calendar(identifier: .gregorian)
                        calendar.timeZone = .current
                        options.end = calendar.date(byAdding: .day, value: 1, to: date)
                    }
                }
            default: throw ImportError(message: "Unknown option: \(argument)")
            }
            index += 1
        }
        if let start = options.start, let end = options.end, start >= end {
            throw ImportError(message: "--from must not be later than --to")
        }
        return options
    }

    func includes(_ date: Date) -> Bool {
        (start == nil || date >= start!) && (end == nil || date < end!)
    }

    func target(name: String, date: Date) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\0") else {
            throw ImportError(message: "Unsafe device filename: \(name)")
        }
        let day = Self.dateFormatter().string(from: date)
        return destination.appendingPathComponent(String(day.prefix(4)), isDirectory: true)
            .appendingPathComponent(day, isDirectory: true).appendingPathComponent(name)
    }
}

let help = """
Usage: swift copy-iphone-photos.swift [options]

  --dest PATH         Destination directory (default: current directory)
  --from YYYY-MM-DD    First date to include (local time, inclusive)
  --to YYYY-MM-DD      Last date to include (local time, inclusive)
  --exclude-movies    Exclude videos, including Live Photo video companions
  --overwrite         Replace existing files, e.g. to refresh edited photos
  --dry-run           List planned copies without downloading or writing files
  --device NAME       Exact device name (otherwise use the first camera found)
  --timeout SECONDS   Maximum idle wait for discovery/catalog/download (default: 120)
  --help, -h          Show this help

Unlock the iPhone and trust this Mac before running. Copies device-exposed media
to YYYY/YYYY-MM-DD/name, skipping existing files unless --overwrite is supplied.
iCloud-only originals may not be exposed over USB; see README.md.
"""

#if os(macOS)
final class Importer: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    let options: Options
    let browser = ICDeviceBrowser()
    var camera: ICCameraDevice?
    var pending: [(ICCameraFile, URL)] = []
    var staging: URL?
    var transfer: Progress?
    var watchdog: Timer?
    var progressTimer: Timer?
    var catalogReady = false
    var finished = false
    var failures = 0
    var copied = 0
    var skipped = 0

    init(options: Options) {
        self.options = options
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(
            rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue)!
    }

    func resetWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: options.timeout, repeats: false) { [weak self] _ in
            self?.fail("Timed out. Unlock/trust the iPhone and check that originals are on the device. Try a longer --timeout for a large library.")
        }
    }

    func fail(_ message: String) {
        fputs("\(message)\n", stderr)
        failures += 1
        finish()
    }

    func finish() {
        guard !finished else { return }
        finished = true
        watchdog?.invalidate()
        progressTimer?.invalidate()
        transfer?.cancel()
        browser.stop()
        camera?.requestCloseSession()
        if let staging = staging { try? FileManager.default.removeItem(at: staging) }
        print("Copied: \(copied); skipped: \(skipped); errors: \(failures)")
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard camera == nil, let camera = device as? ICCameraDevice,
              options.deviceName == nil || camera.name == options.deviceName else { return }
        self.camera = camera
        camera.delegate = self
        print("Opening \(camera.name ?? "camera")…")
        resetWatchdog()
        camera.requestOpenSession()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        if device === camera, !finished { fail("Device disconnected.") }
    }

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if let error = error { fail("Cannot open device: \(error.localizedDescription)") }
        else { resetWatchdog() }
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}
    func deviceDidBecomeReady(_ device: ICDevice) { resetWatchdog() }
    func didRemove(_ device: ICDevice) {
        if !finished { fail("Device disconnected.") }
    }

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) { resetWatchdog() }
    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?,
                      for item: ICCameraItem, error: Error?) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?,
                      for item: ICCameraItem, error: Error?) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) { resetWatchdog() }
    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        print("Unlock the iPhone and accept Trust This Computer.")
        resetWatchdog()
    }

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        guard !finished, !catalogReady else { return }
        catalogReady = true
        do {
            for file in (device.mediaFiles ?? []).compactMap({ $0 as? ICCameraFile }) {
                guard let name = file.name,
                      let date = file.exifCreationDate ?? file.creationDate ?? file.fileCreationDate else {
                    print("Skipping (missing filename or date): \(file.name ?? "unnamed file")")
                    skipped += 1
                    continue
                }
                guard options.includes(date) else { continue }
                var type = file.uti.flatMap { UTType($0) }
                if type?.conforms(to: .image) != true && type?.conforms(to: .movie) != true {
                    type = UTType(filenameExtension: (name as NSString).pathExtension)
                }
                let movie = type?.conforms(to: .movie) == true
                guard type?.conforms(to: .image) == true || movie else { continue }
                if options.excludeMovies && movie { continue }
                let target = try options.target(name: name, date: date)
                if FileManager.default.fileExists(atPath: target.path) && !options.overwrite {
                    print("Skipping (already exists): \(target.path)")
                    skipped += 1
                    continue
                }
                pending.append((file, target))
            }
            pending.sort { $0.1.path > $1.1.path }
            print("Selected \(pending.count) files.")
            if options.dryRun {
                for (_, target) in pending.reversed() { print("[DRY RUN] Would copy: \(target.path)") }
                finish()
            } else {
                downloadNext()
            }
        } catch { fail(error.localizedDescription) }
    }

    func downloadNext() {
        guard !finished else { return }
        guard camera != nil, let (file, target) = pending.popLast() else { finish(); return }
        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: target.path) && !options.overwrite {
                print("Skipping (already exists): \(target.path)")
                skipped += 1
                DispatchQueue.main.async { self.downloadNext() }
                return
            }
            let directory = target.deletingLastPathComponent()
            let root = options.destination.resolvingSymlinksInPath().path
            guard directory.resolvingSymlinksInPath().path.hasPrefix(root == "/" ? root : root + "/") else {
                throw ImportError(message: "Destination date folder escapes --dest: \(directory.path)")
            }
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let staging = directory.appendingPathComponent(".iphone-import-\(UUID().uuidString)", isDirectory: true)
            try manager.createDirectory(at: staging, withIntermediateDirectories: false)
            self.staging = staging
            resetWatchdog()
            transfer = file.requestDownload(options: [
                .downloadsDirectoryURL: staging,
                .saveAsFilename: target.lastPathComponent,
                .overwrite: false,
                .deleteAfterSuccessfulDownload: false
            ]) { [weak self] savedName, error in
                DispatchQueue.main.async {
                    self?.didDownload(file, target: target, savedName: savedName, error: error)
                }
            }
            var previousBytes: Int64 = 0
            progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self = self, let progress = self.transfer else { return }
                if progress.completedUnitCount != previousBytes {
                    previousBytes = progress.completedUnitCount
                    self.resetWatchdog()
                }
            }
        } catch { fail(error.localizedDescription) }
    }

    func didDownload(_ file: ICCameraFile, target: URL, savedName: String?, error: Error?) {
        guard !finished, let staging = staging else { return }
        progressTimer?.invalidate()
        transfer = nil
        do {
            if let error = error { throw error }
            guard let savedName = savedName,
                  (savedName as NSString).lastPathComponent == target.lastPathComponent else {
                throw ImportError(message: "Device returned an unexpected download filename")
            }
            let source = staging.appendingPathComponent(target.lastPathComponent)
            let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
            guard let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
                throw ImportError(message: "Download returned an empty file for \(target.lastPathComponent)")
            }
            if options.overwrite {
                // Same-filesystem rename replaces atomically and does not follow target symlinks.
                guard rename(source.path, target.path) == 0 else {
                    throw ImportError(message: "Cannot replace \(target.path): \(String(cString: strerror(errno)))")
                }
            } else {
                try FileManager.default.moveItem(at: source, to: target)
            }
            copied += 1
            print("Copied: \(target.path)")
        } catch {
            failures += 1
            fputs("Failed \(file.name ?? "file"): \(error.localizedDescription)\n", stderr)
        }
        try? FileManager.default.removeItem(at: staging)
        self.staging = nil
        downloadNext()
    }

    func run() -> Int32 {
        resetWatchdog()
        browser.start()
        while !finished { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1)) }
        return failures == 0 ? 0 : 1
    }
}
#endif

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.contains("--help") || arguments.contains("-h") {
        print(help)
        exit(0)
    }
    let options = try Options.parse(arguments)
    #if os(macOS)
    exit(Importer(options: options).run())
    #else
    throw ImportError(message: "Direct iPhone import requires macOS 11 or later and ImageCaptureCore.")
    #endif
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
