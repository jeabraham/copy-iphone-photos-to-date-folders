#!/usr/bin/env swift
import Foundation

#if canImport(SQLite3)
import SQLite3
#if os(macOS)
import Darwin
#else
import Glibc
#endif
#endif

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
    var adoptExisting = false
    var dryRun = false
    var deviceName: String?
    var deviceID: String?
    var timeout: TimeInterval = 120
    var companion = false
    var port: UInt16 = 58214

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
            case "--adopt-existing": options.adoptExisting = true
            case "--dry-run": options.dryRun = true
            case "--companion": options.companion = true
            case "--dest", "--from", "--to", "--device", "--device-id", "--timeout", "--port":
                index += 1
                guard index < arguments.count, !arguments[index].hasPrefix("--"),
                      !arguments[index].isEmpty else {
                    throw ImportError(message: "Missing value for \(argument)")
                }
                let value = arguments[index]
                switch argument {
                case "--dest": options.destination = URL(fileURLWithPath: value).standardizedFileURL
                case "--device": options.deviceName = value
                case "--device-id": options.deviceID = value
                case "--port":
                    guard let port = UInt16(value), port > 1023 else {
                        throw ImportError(message: "--port must be a number from 1024 to 65535")
                    }
                    options.port = port
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
        if options.adoptExisting && options.overwrite {
            throw ImportError(message: "Use --adopt-existing separately from --overwrite")
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

#if canImport(SQLite3)
struct PhotoRecord {
    let deviceID: String
    let assetID: String
    let relativePath: String
    let complete: Bool
    let savedSize: Int64
}

final class PhotoInventory {
    private var handle: OpaquePointer?
    private var lockDescriptor: Int32 = -1
    let readOnly: Bool

    init(destination: URL, readOnly: Bool) throws {
        self.readOnly = readOnly
        let manager = FileManager.default
        let database = destination.appendingPathComponent(".iphone-import.sqlite3")
        let exists = manager.fileExists(atPath: database.path)
        do {
            if !readOnly {
                try manager.createDirectory(at: destination, withIntermediateDirectories: true)
                let lock = destination.appendingPathComponent(".iphone-import.lock")
                lockDescriptor = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
                guard lockDescriptor >= 0, lockf(lockDescriptor, F_TLOCK, 0) == 0 else {
                    throw ImportError(message: "Cannot lock import inventory. Another importer may be using this destination.")
                }
            }
            if (try? manager.destinationOfSymbolicLink(atPath: database.path)) != nil {
                throw ImportError(message: "Refusing a symlinked import database: \(database.path)")
            }
            let path = readOnly && !exists ? ":memory:" : database.path
            let flags = readOnly && exists ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
            guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
                throw databaseError()
            }
            sqlite3_busy_timeout(handle, 5000)
            let version = try rows("PRAGMA user_version").first?.first
            if version == "0" && (!exists || !readOnly) {
                try rows("""
                    CREATE TABLE IF NOT EXISTS devices (
                        id TEXT PRIMARY KEY, name TEXT NOT NULL
                    )
                    """)
                try rows("""
                    CREATE TABLE IF NOT EXISTS photos (
                        device_id TEXT NOT NULL REFERENCES devices(id),
                        asset_id TEXT NOT NULL,
                        original_name TEXT NOT NULL,
                        capture_date TEXT NOT NULL,
                        source_size INTEGER NOT NULL,
                        modified_date TEXT NOT NULL,
                        relative_path TEXT NOT NULL,
                        path_key TEXT NOT NULL UNIQUE,
                        complete INTEGER NOT NULL DEFAULT 0,
                        saved_size INTEGER NOT NULL DEFAULT 0,
                        PRIMARY KEY (device_id, asset_id)
                    )
                    """)
                try rows("PRAGMA user_version = 1")
            } else if version != "1" {
                throw ImportError(message: "Unsupported import database schema; preserve the database and check the script version.")
            }
        } catch {
            closeInventory()
            throw error
        }
    }

    deinit { closeInventory() }

    private func closeInventory() {
        if let handle = handle { sqlite3_close(handle); self.handle = nil }
        if lockDescriptor >= 0 { _ = close(lockDescriptor); lockDescriptor = -1 }
    }

    private func databaseError() -> ImportError {
        ImportError(message: "Import database error: \(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open database")")
    }

    @discardableResult
    private func rows(_ sql: String, _ values: [String] = []) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let result = value.withCString {
                sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard result == SQLITE_OK else { throw databaseError() }
        }
        var result: [[String]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw databaseError() }
            result.append((0..<sqlite3_column_count(statement)).map {
                sqlite3_column_text(statement, $0).map { String(cString: $0) } ?? ""
            })
        }
    }

    func records() throws -> [PhotoRecord] {
        try rows("SELECT device_id, asset_id, relative_path, complete, saved_size FROM photos").map {
            PhotoRecord(deviceID: $0[0], assetID: $0[1], relativePath: $0[2],
                        complete: $0[3] == "1", savedSize: Int64($0[4]) ?? 0)
        }
    }

    func reserve(_ record: PhotoRecord, deviceName: String, originalName: String,
                 date: Date, sourceSize: Int64, modified: Date?) throws {
        guard !readOnly else { return }
        try rows("BEGIN IMMEDIATE")
        do {
            try rows("INSERT INTO devices (id, name) VALUES (?, ?) ON CONFLICT (id) DO UPDATE SET name = excluded.name",
                     [record.deviceID, deviceName])
            try rows("""
                INSERT INTO photos (device_id, asset_id, original_name, capture_date, source_size,
                    modified_date, relative_path, path_key, complete, saved_size)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (device_id, asset_id) DO UPDATE SET
                    original_name = excluded.original_name, capture_date = excluded.capture_date,
                    source_size = excluded.source_size, modified_date = excluded.modified_date,
                    relative_path = excluded.relative_path, path_key = excluded.path_key,
                    complete = excluded.complete, saved_size = excluded.saved_size
                """, [record.deviceID, record.assetID, originalName, String(date.timeIntervalSince1970),
                      String(sourceSize), modified.map { String($0.timeIntervalSince1970) } ?? "",
                      record.relativePath, Self.pathKey(record.relativePath),
                      record.complete ? "1" : "0", String(record.savedSize)])
            try rows("COMMIT")
        } catch {
            _ = try? rows("ROLLBACK")
            throw error
        }
    }

    func complete(_ record: PhotoRecord, size: Int64) throws {
        try rows("UPDATE photos SET complete = 1, saved_size = ? WHERE device_id = ? AND asset_id = ?",
                 [String(size), record.deviceID, record.assetID])
    }

    static func pathKey(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }
}

struct PhotoPlan {
    let record: PhotoRecord
    let target: URL
    let skip: Bool
    let replace: Bool
    var adopt = false
}

final class PhotoPlanner {
    let options: Options
    private var known: [String: PhotoRecord] = [:]
    private var claimed: Set<String> = []
    private var planned: Set<String> = []

    init(options: Options, records: [PhotoRecord]) throws {
        self.options = options
        for record in records {
            _ = try target(for: record.relativePath)
            known[try key(deviceID: record.deviceID, assetID: record.assetID)] = record
            claimed.insert(PhotoInventory.pathKey(record.relativePath))
        }
    }

    private func key(deviceID: String, assetID: String) throws -> String {
        String(decoding: try JSONEncoder().encode([deviceID, assetID]), as: UTF8.self)
    }

    private func target(for relative: String) throws -> URL {
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !relative.contains("\0") else {
            throw ImportError(message: "Unsafe path in import database: \(relative)")
        }
        let target = options.destination.appendingPathComponent(relative)
        let root = options.destination.resolvingSymlinksInPath().path
        var directory = options.destination.resolvingSymlinksInPath()
        for component in components.dropLast() {
            directory = directory.appendingPathComponent(String(component), isDirectory: true).resolvingSymlinksInPath()
            guard directory.path.hasPrefix(root == "/" ? root : root + "/") else {
                throw ImportError(message: "Import date folder escapes destination: \(relative)")
            }
        }
        return target
    }

    private func exists(_ target: URL) -> Bool {
        FileManager.default.fileExists(atPath: target.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: target.path)) != nil
    }

    func plan(deviceID: String, sourcePath: String, name: String, date: Date, sourceSize: Int64 = 0) throws -> PhotoPlan {
        let assetID = String(decoding: try JSONEncoder().encode([sourcePath, String(date.timeIntervalSince1970)]), as: UTF8.self)
        let identity = try key(deviceID: deviceID, assetID: assetID)
        guard planned.insert(identity).inserted else {
            throw ImportError(message: "Ambiguous duplicate source identity for \(name); refusing to merge distinct catalog entries.")
        }
        if let record = known[identity] {
            let saved = try target(for: record.relativePath)
            if record.complete || !exists(saved) {
                let attributes = try? FileManager.default.attributesOfItem(atPath: saved.path)
                let size = attributes?[.size] as? NSNumber
                let intact = record.complete && size?.int64Value == record.savedSize && record.savedSize > 0
                    && attributes?[.type] as? FileAttributeType == .typeRegular
                if exists(saved) && !intact && !options.overwrite {
                    throw ImportError(message: "Recorded photo has changed or is unreadable: \(saved.path). Use --overwrite to refresh it.")
                }
                return PhotoPlan(record: record, target: saved, skip: intact && !options.overwrite,
                                 replace: record.complete && options.overwrite)
            }
        }
        _ = try options.target(name: name, date: date)
        let day = Options.dateFormatter().string(from: date)
        var relative = "\(day.prefix(4))/\(day)/\(name)"
        let base = try target(for: relative)
        if options.adoptExisting && !claimed.contains(PhotoInventory.pathKey(relative)) && exists(base) {
            let attributes = try FileManager.default.attributesOfItem(atPath: base.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard attributes[.type] as? FileAttributeType == .typeRegular, size > 0, size == sourceSize else {
                throw ImportError(message: "Cannot adopt \(base.path): not a regular file matching the device's size. Verify the file manually or import without --adopt-existing.")
            }
            let record = PhotoRecord(deviceID: deviceID, assetID: assetID, relativePath: relative, complete: true, savedSize: size)
            known[identity] = record
            claimed.insert(PhotoInventory.pathKey(relative))
            return PhotoPlan(record: record, target: base, skip: true, replace: false, adopt: true)
        }
        // A deterministic non-cryptographic token is only a filename hint; DB ownership is authoritative.
        var token: UInt64 = 14695981039346656037
        for byte in deviceID.utf8 { token = (token ^ UInt64(byte)) &* 1099511628211 }
        let suffix = String(token, radix: 16)
        var counter = 0
        while try claimed.contains(PhotoInventory.pathKey(relative)) || exists(target(for: relative)) {
            counter += 1
            let ext = base.pathExtension
            let stem = (name as NSString).deletingPathExtension
            let ending = counter == 1 ? "" : "_\(counter)"
            relative = "\(day.prefix(4))/\(day)/\(stem)__\(suffix)\(ending)\(ext.isEmpty ? "" : "." + ext)"
        }
        let record = PhotoRecord(deviceID: deviceID, assetID: assetID, relativePath: relative, complete: false, savedSize: 0)
        known[identity] = record
        claimed.insert(PhotoInventory.pathKey(relative))
        return PhotoPlan(record: record, target: try target(for: relative), skip: false, replace: false)
    }
}
#endif

let help = """
Usage: swift copy-iphone-photos.swift [options]

  --dest PATH         Destination directory (default: current directory)
  --from YYYY-MM-DD    First date to include (local time, inclusive)
  --to YYYY-MM-DD      Last date to include (local time, inclusive)
  --exclude-movies    Exclude videos, including Live Photo video companions
  --overwrite         Replace existing files, e.g. to refresh edited photos
  --adopt-existing    Attribute untracked filename/date/size matches to this phone
  --dry-run           List planned copies without downloading or writing files
  --device NAME       Exact device name (otherwise use the first camera found)
  --device-id ID      Stable device identity override (required if no serial number)
  --companion         Pull originals over USB from the iOS companion app instead of Image Capture
  --port N            Companion app TCP port (default: 58214)
  --timeout SECONDS   Maximum idle wait for discovery/catalog/download (default: 120)
  --help, -h          Show this help

Unlock the iPhone and trust this Mac before running. Copies device-exposed media
to YYYY/YYYY-MM-DD/name, tracking device ownership in a destination-local SQLite DB.
iCloud-only originals may not be exposed over USB; see README.md.
"""

#if os(macOS)
final class Importer: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    let options: Options
    let browser = ICDeviceBrowser()
    var camera: ICCameraDevice?
    var pending: [(ICCameraFile, PhotoPlan)] = []
    var inventory: PhotoInventory?
    var staging: URL?
    var transfer: Progress?
    var watchdog: Timer?
    var progressTimer: Timer?
    var openRetry: Timer?
    var openingSession = false
    var accessDeadline: Date?
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
        openRetry?.invalidate()
        transfer?.cancel()
        browser.stop()
        camera?.requestCloseSession()
        if let staging = staging { try? FileManager.default.removeItem(at: staging) }
        inventory = nil
        print("Copied: \(copied); skipped: \(skipped); errors: \(failures)")
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard camera == nil, let camera = device as? ICCameraDevice,
              options.deviceName == nil || camera.name == options.deviceName else { return }
        self.camera = camera
        camera.delegate = self
        print("Opening \(camera.name ?? "camera")…")
        resetWatchdog()
        openCameraSession()
    }

    func openCameraSession() {
        guard !finished, !openingSession, let camera = camera,
              !camera.hasOpenSession else { return }
        if let deadline = accessDeadline, Date() >= deadline {
            fail("Timed out waiting for iPhone media access. If the phone is already unlocked, quit Image Capture/Photos, reconnect, and check this tool's macOS permissions.")
            return
        }
        openingSession = true
        camera.requestOpenSession()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        if device === camera, !finished { fail("Device disconnected.") }
    }

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        guard device === camera, !finished else { return }
        openingSession = false
        guard let error = error else {
            openRetry?.invalidate()
            openRetry = nil
            accessDeadline = nil
            resetWatchdog()
            return
        }
        let details = error as NSError
        let description = "\(details.domain) \(details.code): \(details.localizedDescription)"
        guard details.domain == ICErrorDomain,
              details.code == ICReturn.deviceIsPasscodeLocked.rawValue else {
            fail("Cannot open device: \(description)")
            return
        }
        if accessDeadline == nil {
            accessDeadline = Date(timeIntervalSinceNow: options.timeout)
            print("ImageCaptureCore reports restricted media access (\(description)). Waiting and retrying; this does not necessarily mean the screen is locked. Quit other importing apps and check macOS permissions if already unlocked.")
        }
        openRetry?.invalidate()
        openRetry = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            self?.openCameraSession()
        }
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
    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        guard device === camera, !finished else { return }
        openRetry?.invalidate()
        openRetry = nil
        resetWatchdog()
        openCameraSession()
    }
    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        guard device === camera, !finished else { return }
        print("iPhone media access is restricted. Waiting for access; unlock/trust the phone if needed.")
    }

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        guard !finished, !catalogReady, !device.isAccessRestrictedAppleDevice else { return }
        catalogReady = true
        do {
            let identity: String
            if let override = options.deviceID {
                identity = "manual:\(override)"
            } else if let serial = device.serialNumberString, !serial.isEmpty {
                identity = "serial:\(serial)"
            } else {
                throw ImportError(message: "Device supplies no serial number. Pass --device-id with a unique, permanent label for this phone, and reuse it on every import.")
            }
            let inventory = try PhotoInventory(destination: options.destination, readOnly: options.dryRun)
            self.inventory = inventory
            let planner = try PhotoPlanner(options: options, records: inventory.records())
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
                var components = [name]
                var folder = file.parentFolder
                while let parent = folder {
                    guard let folderName = parent.name else {
                        throw ImportError(message: "Missing source folder name for \(name); cannot build a reliable inventory key.")
                    }
                    components.insert(folderName, at: 0)
                    folder = parent.parentFolder
                }
                let sourcePath = String(decoding: try JSONEncoder().encode(components), as: UTF8.self)
                let plan = try planner.plan(deviceID: identity, sourcePath: sourcePath, name: name,
                                            date: date, sourceSize: Int64(file.fileSize))
                if plan.skip {
                    if plan.adopt {
                        try inventory.reserve(plan.record, deviceName: device.name ?? "camera", originalName: name,
                                              date: date, sourceSize: Int64(file.fileSize), modified: file.modificationDate)
                        print("\(options.dryRun ? "[DRY RUN] Would adopt" : "Adopted") existing file for this device: \(plan.target.path)")
                    } else {
                        print("Skipping (already imported from this device): \(plan.target.path)")
                    }
                    skipped += 1
                    continue
                }
                pending.append((file, plan))
            }
            pending.sort { $0.1.target.path > $1.1.target.path }
            print("Selected \(pending.count) files.")
            if options.dryRun {
                for (_, plan) in pending.reversed() { print("[DRY RUN] Would copy: \(plan.target.path)") }
                finish()
            } else {
                downloadNext()
            }
        } catch { fail(error.localizedDescription) }
    }

    func downloadNext() {
        guard !finished else { return }
        guard let camera = camera, let inventory = inventory,
              let (file, plan) = pending.popLast() else { finish(); return }
        let target = plan.target
        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: target.path) && !plan.replace {
                throw ImportError(message: "Target appeared after planning; refusing to overwrite it: \(target.path). Rerun to resolve the collision.")
            }
            guard let name = file.name,
                  let date = file.exifCreationDate ?? file.creationDate ?? file.fileCreationDate else {
                throw ImportError(message: "Source metadata disappeared before download")
            }
            try inventory.reserve(plan.record, deviceName: camera.name ?? "camera", originalName: name,
                                  date: date, sourceSize: Int64(file.fileSize), modified: file.modificationDate)
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
                    self?.didDownload(file, plan: plan, savedName: savedName, error: error)
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

    func didDownload(_ file: ICCameraFile, plan: PhotoPlan, savedName: String?, error: Error?) {
        guard !finished, let staging = staging, let inventory = inventory else { return }
        let target = plan.target
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
            if plan.replace {
                // Same-filesystem rename replaces atomically and does not follow target symlinks.
                guard rename(source.path, target.path) == 0 else {
                    throw ImportError(message: "Cannot replace \(target.path): \(String(cString: strerror(errno)))")
                }
            } else {
                try FileManager.default.moveItem(at: source, to: target)
            }
            try inventory.complete(plan.record, size: size.int64Value)
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

// Blocking socket with frames [UInt32 BE length][UInt8 kind][payload]; kind 0 = JSON, 1 = file data.
final class CompanionChannel {
    let descriptor: Int32

    init(descriptor: Int32, timeout: TimeInterval) {
        self.descriptor = descriptor
        var value = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    deinit { close(descriptor) }

    static func unixSocket(path: String, timeout: TimeInterval) throws -> CompanionChannel {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ImportError(message: "Cannot create socket") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(descriptor)
            throw ImportError(message: "usbmuxd socket path is too long: \(path)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            bytes.withUnsafeBytes { buffer.copyMemory(from: $0) }
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(descriptor)
            throw ImportError(message: "Cannot reach usbmuxd at \(path): \(String(cString: strerror(errno)))")
        }
        return CompanionChannel(descriptor: descriptor, timeout: timeout)
    }

    func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = send(descriptor, buffer.baseAddress! + offset, buffer.count - offset, 0)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw ImportError(message: "Connection to the iPhone closed while sending") }
                offset += written
            }
        }
    }

    func readExactly(_ count: Int) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { buffer in
            while offset < count {
                let received = recv(descriptor, buffer.baseAddress! + offset, count - offset, 0)
                if received < 0 && errno == EINTR { continue }
                if received < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    throw ImportError(message: "Timed out waiting for the iPhone. Keep the companion app open and unlocked, or raise --timeout.")
                }
                guard received > 0 else { throw ImportError(message: "Connection to the iPhone closed. Is the companion app still in the foreground?") }
                offset += received
            }
        }
        return data
    }

    func sendJSON(_ object: [String: Any]) throws {
        let payload = try JSONSerialization.data(withJSONObject: object)
        var frame = Data()
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(0)
        frame.append(payload)
        try writeAll(frame)
    }

    func readFrame() throws -> (kind: UInt8, payload: Data) {
        let header = try readExactly(5)
        let length = Int(header.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        guard length <= 64 * 1024 * 1024 else { throw ImportError(message: "Oversized frame from the iPhone") }
        return (header[4], try readExactly(length))
    }

    func readJSON() throws -> [String: Any] {
        let frame = try readFrame()
        guard frame.kind == 0, let object = try JSONSerialization.jsonObject(with: frame.payload) as? [String: Any] else {
            throw ImportError(message: "Unexpected response from the iPhone")
        }
        return object
    }
}

// Talks to usbmuxd (the macOS USB multiplexer) to open a TCP stream to the phone's loopback port.
enum USBMux {
    // Honors the libimobiledevice-style override, e.g. USBMUXD_SOCKET_ADDRESS=UNIX:/tmp/usbmuxd.
    static var socketPath: String {
        if let override = ProcessInfo.processInfo.environment["USBMUXD_SOCKET_ADDRESS"],
           override.hasPrefix("UNIX:") { return String(override.dropFirst(5)) }
        return "/var/run/usbmuxd"
    }

    static func request(_ channel: CompanionChannel, _ message: [String: Any]) throws -> [String: Any] {
        var body = message
        body["ClientVersionString"] = "copy-iphone-photos"
        body["ProgName"] = "copy-iphone-photos"
        let plist = try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
        var packet = Data()
        for value in [UInt32(16 + plist.count), 1, 8, 1] {
            withUnsafeBytes(of: value.littleEndian) { packet.append(contentsOf: $0) }
        }
        packet.append(plist)
        try channel.writeAll(packet)
        let header = try channel.readExactly(16)
        let length = Int(header.prefix(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) })
        guard length >= 16, length < 16 * 1024 * 1024 else { throw ImportError(message: "Invalid usbmuxd response") }
        let response = try channel.readExactly(length - 16)
        guard let result = try PropertyListSerialization.propertyList(from: response, format: nil) as? [String: Any] else {
            throw ImportError(message: "Invalid usbmuxd response")
        }
        return result
    }

    static func usbDevice(timeout: TimeInterval) throws -> (id: Int, serial: String) {
        let channel = try CompanionChannel.unixSocket(path: socketPath, timeout: timeout)
        let response = try request(channel, ["MessageType": "ListDevices"])
        let devices = (response["DeviceList"] as? [[String: Any]] ?? []).compactMap { entry -> (Int, String)? in
            guard let properties = entry["Properties"] as? [String: Any],
                  properties["ConnectionType"] as? String == "USB",
                  let id = (properties["DeviceID"] as? NSNumber)?.intValue,
                  let serial = properties["SerialNumber"] as? String else { return nil }
            return (id, serial)
        }
        guard devices.count == 1 else {
            throw ImportError(message: devices.isEmpty
                ? "No USB-connected iPhone found. Connect it, unlock it, and tap Trust."
                : "Several USB devices are connected; connect only one iPhone.")
        }
        return (devices[0].0, devices[0].1)
    }

    static func connect(deviceID: Int, port: UInt16, timeout: TimeInterval) throws -> CompanionChannel {
        let channel = try CompanionChannel.unixSocket(path: socketPath, timeout: timeout)
        let response = try request(channel, ["MessageType": "Connect", "DeviceID": deviceID,
                                             "PortNumber": Int(port.bigEndian)])
        let code = (response["Number"] as? NSNumber)?.intValue ?? -1
        switch code {
        case 0: return channel
        case 3: throw ImportError(message: "The companion app is not listening on port \(port). Open it on the iPhone and keep it in the foreground.")
        default: throw ImportError(message: "usbmuxd could not connect to the iPhone (code \(code)). Unlock it and trust this Mac.")
        }
    }
}

final class CompanionImporter {
    let options: Options
    var copied = 0
    var skipped = 0
    var failures = 0

    init(options: Options) { self.options = options }

    func run() -> Int32 {
        do {
            let device = try USBMux.usbDevice(timeout: options.timeout)
            let channel = try USBMux.connect(deviceID: device.id, port: options.port, timeout: options.timeout)
            try channel.sendJSON(["op": "hello"])
            let hello = try channel.readJSON()
            guard hello["ok"] as? Bool == true else { throw ImportError(message: "Companion app refused the connection") }
            if hello["authorized"] as? Bool != true {
                throw ImportError(message: "Grant the companion app full Photos access (Settings → Photos), then rerun.")
            }
            let name = hello["name"] as? String ?? "iPhone"
            print("Connected to \(name) over USB.")
            let identity = options.deviceID.map { "manual:\($0)" } ?? "companion:\(device.serial)"
            var request: [String: Any] = ["op": "list", "excludeMovies": options.excludeMovies]
            if let start = options.start { request["from"] = start.timeIntervalSince1970 }
            if let end = options.end { request["to"] = end.timeIntervalSince1970 }
            try channel.sendJSON(request)
            let list = try channel.readJSON()
            guard list["ok"] as? Bool == true, let assets = list["assets"] as? [[String: Any]] else {
                throw ImportError(message: list["error"] as? String ?? "Could not list photos")
            }
            let inventory = try PhotoInventory(destination: options.destination, readOnly: options.dryRun)
            let planner = try PhotoPlanner(options: options, records: inventory.records())
            var pending: [(asset: String, type: String, name: String, date: Date, plan: PhotoPlan)] = []
            for asset in assets {
                guard let id = asset["id"] as? String, let seconds = asset["date"] as? Double,
                      let resources = asset["resources"] as? [[String: Any]] else { continue }
                let date = Date(timeIntervalSince1970: seconds)
                for resource in resources {
                    guard let type = resource["type"] as? String, let file = resource["name"] as? String else { continue }
                    let sourcePath = String(decoding: try JSONEncoder().encode(["companion", id, type, file]), as: UTF8.self)
                    let plan = try planner.plan(deviceID: identity, sourcePath: sourcePath, name: file, date: date)
                    if plan.skip {
                        print("Skipping (already imported from this device): \(plan.target.path)")
                        skipped += 1
                    } else {
                        pending.append((id, type, file, date, plan))
                    }
                }
            }
            pending.sort { $0.plan.target.path < $1.plan.target.path }
            print("Selected \(pending.count) files.")
            for item in pending {
                if options.dryRun {
                    print("[DRY RUN] Would copy: \(item.plan.target.path)")
                    continue
                }
                do {
                    try fetch(item, channel: channel, inventory: inventory, deviceName: name)
                } catch let error as ImportError where error.message.hasPrefix("Fetch failed") {
                    failures += 1
                    fputs("\(error.message)\n", stderr)
                }
            }
        } catch {
            failures += 1
            fputs("\(error.localizedDescription)\n", stderr)
        }
        print("Copied: \(copied); skipped: \(skipped); errors: \(failures)")
        return failures == 0 ? 0 : 1
    }

    // Connection-level errors propagate and abort the run; per-asset failures are reported and skipped.
    func fetch(_ item: (asset: String, type: String, name: String, date: Date, plan: PhotoPlan),
               channel: CompanionChannel, inventory: PhotoInventory, deviceName: String) throws {
        let manager = FileManager.default
        let plan = item.plan
        let target = plan.target
        if manager.fileExists(atPath: target.path) && !plan.replace {
            throw ImportError(message: "Fetch failed: target appeared after planning; refusing to overwrite it: \(target.path)")
        }
        try inventory.reserve(plan.record, deviceName: deviceName, originalName: item.name,
                              date: item.date, sourceSize: 0, modified: nil)
        let directory = target.deletingLastPathComponent()
        let root = options.destination.resolvingSymlinksInPath().path
        guard directory.resolvingSymlinksInPath().path.hasPrefix(root == "/" ? root : root + "/") else {
            throw ImportError(message: "Destination date folder escapes --dest: \(directory.path)")
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".iphone-import-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        let partial = staging.appendingPathComponent(target.lastPathComponent)
        guard manager.createFile(atPath: partial.path, contents: nil) else {
            throw ImportError(message: "Cannot create \(partial.path)")
        }
        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        try channel.sendJSON(["op": "fetch", "id": item.asset, "type": item.type, "name": item.name])
        var received: Int64 = 0
        while true {
            let frame = try channel.readFrame()
            if frame.kind == 1 {
                try handle.write(contentsOf: frame.payload)
                received += Int64(frame.payload.count)
                continue
            }
            guard let status = try JSONSerialization.jsonObject(with: frame.payload) as? [String: Any] else {
                throw ImportError(message: "Unexpected response from the iPhone")
            }
            guard status["ok"] as? Bool == true else {
                throw ImportError(message: "Fetch failed for \(item.name): \(status["error"] as? String ?? "unknown error")")
            }
            guard (status["bytes"] as? NSNumber)?.int64Value == received, received > 0 else {
                throw ImportError(message: "Fetch failed for \(item.name): received \(received) bytes, expected a different size")
            }
            break
        }
        try handle.close()
        if plan.replace {
            guard rename(partial.path, target.path) == 0 else {
                throw ImportError(message: "Cannot replace \(target.path): \(String(cString: strerror(errno)))")
            }
        } else {
            try manager.moveItem(at: partial, to: target)
        }
        try inventory.complete(plan.record, size: received)
        copied += 1
        print("Copied: \(target.path)")
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
    exit(options.companion ? CompanionImporter(options: options).run() : Importer(options: options).run())
    #else
    throw ImportError(message: "Direct iPhone import requires macOS 11 or later and ImageCaptureCore.")
    #endif
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
