import Foundation
import SQLite3
import Testing
@testable import ImporterCoreLibrary

private final class Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let date = Date(timeIntervalSince1970: 1_794_120_564)
    var options: Options {
        var value = Options()
        value.destination = root
        return value
    }

    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: root) }

    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func reserve(_ plan: PhotoPlan, in inventory: PhotoInventory) throws {
        try inventory.reserve(plan.record, deviceName: "Phone", originalName: "IMG_3907.HEIC",
                              date: date, sourceSize: 4, modified: nil)
    }

    func plan(_ planner: PhotoPlanner, path: String = "DCIM/a/IMG_3907.HEIC", phone: String = "phone-A") throws -> PhotoPlan {
        try planner.plan(deviceID: phone, sourcePath: path, name: "IMG_3907.HEIC", date: date, sourceSize: 4)
    }
}

@Test(arguments: 0..<8)
func deletedImportPolicy(combination: Int) throws {
    let redownload = combination & 1 != 0
    let overwrite = combination & 2 != 0
    let complete = combination & 4 != 0
    let f = try Fixture()
    let inventory = try PhotoInventory(destination: f.root, readOnly: false)
    let initial = try f.plan(PhotoPlanner(options: f.options, records: []))
    try f.reserve(initial, in: inventory)
    if complete { try inventory.complete(initial.record, size: 4) }
    var options = f.options
    options.redownloadDeletedFiles = redownload
    options.overwrite = overwrite
    let result = try f.plan(PhotoPlanner(options: options, records: inventory.records()))
    #expect(result.skip == (complete && !redownload))
    #expect(result.deleted == (complete && !redownload))
    #expect(result.target == initial.target)
}

@Test
func aliasesPersistAndRestoreOnlyOnce() throws {
    let f = try Fixture()
    do {
        let inventory = try PhotoInventory(destination: f.root, readOnly: false)
        let planner = try PhotoPlanner(options: f.options, records: [])
        let first = try f.plan(planner)
        let second = try f.plan(planner, path: "DCIM/b/IMG_3907.HEIC")
        try f.reserve(first, in: inventory)
        try f.write(Data([1, 2, 3, 4]), to: first.target)
        try inventory.complete(first.record, size: 4)
        try f.reserve(second, in: inventory)
        let download = f.root.appendingPathComponent("download")
        try f.write(Data([1, 2, 3, 4]), to: download)
        #expect(try inventory.reuseIdenticalDownload(second.record, downloaded: download, size: 4, options: f.options) == first.target)
        #expect(!FileManager.default.fileExists(atPath: second.target.path))
    }
    let inventory = try PhotoInventory(destination: f.root, readOnly: false)
    let records = try inventory.records()
    #expect(records.count == 1)
    #expect(records.first?.aliases.count == 1)
    let planner = try PhotoPlanner(options: f.options, records: records)
    let first = try f.plan(planner)
    let alias = try f.plan(planner, path: "DCIM/b/IMG_3907.HEIC")
    #expect(first.skip && alias.skip)
    #expect(first.target == alias.target)
    try FileManager.default.removeItem(at: first.target)
    let deletedPlanner = try PhotoPlanner(options: f.options, records: records)
    #expect(try f.plan(deletedPlanner).deleted)
    #expect(try f.plan(deletedPlanner, path: "DCIM/b/IMG_3907.HEIC").deleted)
    var restore = f.options
    restore.redownloadDeletedFiles = true
    let restorePlanner = try PhotoPlanner(options: restore, records: records)
    #expect(try !f.plan(restorePlanner).skip)
    #expect(try f.plan(restorePlanner, path: "DCIM/b/IMG_3907.HEIC").skip)
}

@Test(arguments: [false, true], [false, true])
func onlyIdenticalBytesOnSamePhoneAreMerged(samePhone: Bool, sameBytes: Bool) throws {
    let f = try Fixture()
    let inventory = try PhotoInventory(destination: f.root, readOnly: false)
    let planner = try PhotoPlanner(options: f.options, records: [])
    let first = try f.plan(planner)
    try f.reserve(first, in: inventory)
    try f.write(Data([1, 2, 3, 4]), to: first.target)
    try inventory.complete(first.record, size: 4)
    let next = try f.plan(planner, path: "companion/asset/photo", phone: samePhone ? "phone-A" : "phone-B")
    try f.reserve(next, in: inventory)
    let download = f.root.appendingPathComponent("download")
    try f.write(Data(sameBytes ? [1, 2, 3, 4] : [4, 3, 2, 1]), to: download)
    let existing = try inventory.reuseIdenticalDownload(next.record, downloaded: download, size: 4, options: f.options)
    #expect((existing != nil) == (samePhone && sameBytes))
}

@Test
func oldSettingsAndCommandLine() throws {
    let old = Data(#"{"includeVideos":true,"overwrite":true,"dryRun":false,"adoptExisting":true,"fromDate":"2026-11-06"}"#.utf8)
    var settings = try JSONDecoder().decode(ImportSettings.self, from: old)
    #expect(!settings.redownloadDeletedFiles)
    #expect(settings.includeVideos && settings.overwrite)
    #expect(settings.fromDate == "2026-11-06")
    settings.redownloadDeletedFiles = true
    let restored = try JSONDecoder().decode(ImportSettings.self, from: JSONEncoder().encode(settings))
    #expect(restored == settings)
    #expect(try Options.parse([]).redownloadDeletedFiles == false)
    #expect(try Options.parse(["--redownload-deleted-files"]).redownloadDeletedFiles)
}

@Test
func versionOneInventoryMigratesWithoutLosingHistory() throws {
    let f = try Fixture()
    do {
        let inventory = try PhotoInventory(destination: f.root, readOnly: false)
        let plan = try f.plan(PhotoPlanner(options: f.options, records: []))
        try f.reserve(plan, in: inventory)
        try inventory.complete(plan.record, size: 4)
    }
    var handle: OpaquePointer?
    #expect(sqlite3_open(f.root.appendingPathComponent(".iphone-import.sqlite3").path, &handle) == SQLITE_OK)
    #expect(sqlite3_exec(handle, "DROP TABLE photo_aliases; PRAGMA user_version = 1;", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(handle)
    do {
        let old = try PhotoInventory(destination: f.root, readOnly: true)
        #expect(try old.records().count == 1)
    }
    do {
        let migrated = try PhotoInventory(destination: f.root, readOnly: false)
        let records = try migrated.records()
        #expect(records.count == 1)
        #expect(records.first?.complete == true)
        #expect(records.first?.savedSize == 4)
    }
    let reopened = try PhotoInventory(destination: f.root, readOnly: true)
    #expect(try reopened.records().count == 1)
}
