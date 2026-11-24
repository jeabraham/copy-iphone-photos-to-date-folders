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
        try inventory.reserve(plan.record, deviceName: "Phone", originalName: plan.record.originalName,
                              date: plan.record.date, sourceSize: 4, modified: nil)
    }

    func plan(_ planner: PhotoPlanner, phone: String = "phone-A", date: Date? = nil) throws -> PhotoPlan {
        try planner.plan(deviceID: phone, name: "IMG_3907.HEIC", date: date ?? self.date, sourceSize: 4)
    }

    func legacyPlan(path: String, savedName: String = "IMG_3907.HEIC", date: Date? = nil) throws -> PhotoPlan {
        let date = date ?? self.date
        let target = try options.target(name: savedName, date: date)
        let assetID = String(decoding: try JSONEncoder().encode([path, String(date.timeIntervalSince1970)]), as: UTF8.self)
        let record = PhotoRecord(deviceID: "phone-A", assetID: assetID,
                                 relativePath: String(target.path.dropFirst(root.path.count + 1)),
                                 complete: false, savedSize: 0, originalName: "IMG_3907.HEIC", date: date)
        return PhotoPlan(record: record, target: target, skip: false, replace: false)
    }
}

@Test(arguments: 0..<8, [false, true])
func deletedImportPolicy(combination: Int, legacy: Bool) throws {
    let redownload = combination & 1 != 0
    let overwrite = combination & 2 != 0
    let complete = combination & 4 != 0
    let f = try Fixture()
    let inventory = try PhotoInventory(destination: f.root, readOnly: false)
    let initial = try legacy ? f.legacyPlan(path: "DCIM/a/IMG_3907.HEIC")
        : f.plan(PhotoPlanner(options: f.options, records: []))
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
        let first = try f.legacyPlan(path: "DCIM/a/IMG_3907.HEIC")
        let second = try f.legacyPlan(path: "DCIM/b/IMG_3907.HEIC", savedName: "IMG_3907__old.HEIC")
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
    let alias = try f.plan(planner)
    #expect(first.skip && alias.skip)
    #expect(first.target == alias.target)
    try FileManager.default.removeItem(at: first.target)
    let deletedPlanner = try PhotoPlanner(options: f.options, records: records)
    #expect(try f.plan(deletedPlanner).deleted)
    #expect(try f.plan(deletedPlanner).deleted)
    var restore = f.options
    restore.redownloadDeletedFiles = true
    let restorePlanner = try PhotoPlanner(options: restore, records: records)
    #expect(try !f.plan(restorePlanner).skip)
    #expect(try f.plan(restorePlanner).skip)
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
    let next = try f.plan(planner, phone: samePhone ? "phone-A" : "phone-B",
                          date: f.date.addingTimeInterval(2))
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
        let plan = try f.legacyPlan(path: "DCIM/a/IMG_3907.HEIC")
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
        #expect(try f.plan(PhotoPlanner(options: f.options, records: old.records())).deleted)
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

@Test(arguments: ["direct", "companion"], [false, true])
func oldPhoneImportsMatchWithoutDownloading(mode: String, deleted: Bool) throws {
    let f = try Fixture()
    let path = String(decoding: try JSONEncoder().encode(
        mode == "direct" ? ["DCIM", "100APPLE", "IMG_3907.HEIC"]
            : ["companion", "old-local-identifier", "photo", "IMG_3907.HEIC"]
    ), as: UTF8.self)
    let legacy = try f.legacyPlan(path: path, date: f.date.addingTimeInterval(0.75))
    do {
        let inventory = try PhotoInventory(destination: f.root, readOnly: false)
        try f.reserve(legacy, in: inventory)
        if !deleted { try f.write(Data([1, 2, 3, 4]), to: legacy.target) }
        try inventory.complete(legacy.record, size: 4)
    }
    let database = f.root.appendingPathComponent(".iphone-import.sqlite3")
    let before = try Data(contentsOf: database)
    var options = f.options
    options.dryRun = true
    let inventory = try PhotoInventory(destination: f.root, readOnly: true)
    let planner = try PhotoPlanner(options: options, records: inventory.records())
    let result = try planner.plan(deviceID: "phone-A", name: "IMG_3907.HEIC", date: f.date, sourceSize: 0)
    #expect(result.skip)
    #expect(result.deleted == deleted)
    #expect(result.record.assetID == legacy.record.assetID)
    #expect(result.target == legacy.target)
    #expect(try Data(contentsOf: database) == before)
}

@Test
func metadataIdentityUsesSourceFilenameAndWholeTimestamp() throws {
    let f = try Fixture()
    let planner = try PhotoPlanner(options: f.options, records: [])
    let first = try f.plan(planner, date: f.date.addingTimeInterval(0.1))
    let same = try f.plan(planner, date: f.date.addingTimeInterval(0.9))
    #expect(!first.skip && same.skip)
    #expect(first.record.assetID == same.record.assetID)
    #expect(first.target == same.target)
    let later = try f.plan(planner, date: f.date.addingTimeInterval(1))
    let otherPhone = try f.plan(planner, phone: "phone-B")
    let otherName = try planner.plan(deviceID: "phone-A", name: "IMG_3907.MOV", date: f.date)
    #expect(!later.skip && !otherPhone.skip && !otherName.skip)
    #expect(Set([first.target, later.target, otherPhone.target, otherName.target]).count == 4)
}

@Test
func historicalConflictsPreserveBothCopiesAndReportAmbiguity() throws {
    let f = try Fixture()
    let inventory = try PhotoInventory(destination: f.root, readOnly: false)
    let first = try f.legacyPlan(path: "DCIM/a/IMG_3907.HEIC")
    let second = try f.legacyPlan(path: "DCIM/b/IMG_3907.HEIC", savedName: "IMG_3907__old.HEIC")
    for (plan, bytes) in [(first, Data([1, 2, 3, 4])), (second, Data([4, 3, 2, 1]))] {
        try f.reserve(plan, in: inventory)
        try f.write(bytes, to: plan.target)
        try inventory.complete(plan.record, size: 4)
    }
    let planner = try PhotoPlanner(options: f.options, records: inventory.records())
    #expect(throws: ImportError.self) { try f.plan(planner) }
    #expect(try inventory.records().count == 2)
    #expect(try Data(contentsOf: first.target) == Data([1, 2, 3, 4]))
    #expect(try Data(contentsOf: second.target) == Data([4, 3, 2, 1]))
}

@Test(arguments: [false, true])
func byteVerifiedAliasDatesRemainRecognizedAfterReopening(legacy: Bool) throws {
    let f = try Fixture()
    let aliasDate = f.date.addingTimeInterval(10)
    do {
        let inventory = try PhotoInventory(destination: f.root, readOnly: false)
        let planner = try PhotoPlanner(options: f.options, records: [])
        let first = try legacy ? f.legacyPlan(path: "DCIM/a/IMG_3907.HEIC") : f.plan(planner)
        let alias = try legacy
            ? f.legacyPlan(path: "DCIM/b/IMG_3907.HEIC", savedName: "IMG_3907__old.HEIC", date: aliasDate)
            : f.plan(planner, date: aliasDate)
        try f.reserve(first, in: inventory)
        try f.write(Data([1, 2, 3, 4]), to: first.target)
        try inventory.complete(first.record, size: 4)
        try f.reserve(alias, in: inventory)
        let download = f.root.appendingPathComponent("download")
        try f.write(Data([1, 2, 3, 4]), to: download)
        #expect(try inventory.reuseIdenticalDownload(alias.record, downloaded: download,
                                                     size: 4, options: f.options) == first.target)
    }
    let inventory = try PhotoInventory(destination: f.root, readOnly: true)
    let planner = try PhotoPlanner(options: f.options, records: inventory.records())
    let first = try f.plan(planner)
    let alias = try f.plan(planner, date: aliasDate)
    #expect(first.skip && alias.skip)
    #expect(first.target == alias.target)
}

@Test
func interruptedLegacyImportKeepsItsIDWhenAnUncommittedFileExists() throws {
    let f = try Fixture()
    let legacy = try f.legacyPlan(path: "DCIM/a/IMG_3907.HEIC")
    do {
        let inventory = try PhotoInventory(destination: f.root, readOnly: false)
        try f.reserve(legacy, in: inventory)
        try f.write(Data([4, 3, 2, 1]), to: legacy.target)
        let retry = try f.plan(PhotoPlanner(options: f.options, records: inventory.records()))
        #expect(!retry.skip && !retry.replace)
        #expect(retry.record.assetID == legacy.record.assetID)
        #expect(retry.target != legacy.target)
        try f.reserve(retry, in: inventory)
        try f.write(Data([1, 2, 3, 4]), to: retry.target)
        try inventory.complete(retry.record, size: 4)
    }
    let inventory = try PhotoInventory(destination: f.root, readOnly: true)
    #expect(try inventory.records().count == 1)
    #expect(try f.plan(PhotoPlanner(options: f.options, records: inventory.records())).skip)
    #expect(try Data(contentsOf: legacy.target) == Data([4, 3, 2, 1]))
}

@Test(arguments: [false, true])
func legacyMetadataMatchPreservesOverwriteProtection(altered: Bool) throws {
    let f = try Fixture()
    let inventory = try PhotoInventory(destination: f.root, readOnly: false)
    let legacy = try f.legacyPlan(path: "DCIM/a/IMG_3907.HEIC")
    try f.reserve(legacy, in: inventory)
    try f.write(Data(altered ? [1, 2, 3] : [1, 2, 3, 4]), to: legacy.target)
    try inventory.complete(legacy.record, size: 4)
    let planner = try PhotoPlanner(options: f.options, records: inventory.records())
    if altered {
        #expect(throws: ImportError.self) { try f.plan(planner) }
    } else {
        #expect(try f.plan(planner).skip)
    }
    var options = f.options
    options.overwrite = true
    let refresh = try f.plan(PhotoPlanner(options: options, records: inventory.records()))
    #expect(!refresh.skip && refresh.replace)
    #expect(refresh.target == legacy.target)
    #expect(refresh.record.assetID == legacy.record.assetID)
}
