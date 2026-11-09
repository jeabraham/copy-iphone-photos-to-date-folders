import Foundation
import Testing
@testable import ImporterCoreLibrary

private final class CardFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var source: ImportSource
    var settings = ImportSettings()
    var destination: URL { root.appendingPathComponent("destination") }
    var job: ImportJob { ImportJob(source: source, mode: .card, destination: destination, settings: settings) }
    var messages: [String] = []

    init() throws {
        source = ImportSource(kind: .card, label: "Card", location: root.appendingPathComponent("card").path)
        settings.adoptExisting = false
        try FileManager.default.createDirectory(atPath: source.location, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func write(_ name: String = "DCIM/IMG_0001.JPG", bytes: [UInt8] = [1, 2, 3, 4]) throws -> URL {
        let file = URL(fileURLWithPath: source.location).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: file)
        return file
    }

    func run(isCancelled: () -> Bool = { false }) -> Int32 {
        messages = []
        return CardImporter.run(job: job, isCancelled: isCancelled, log: { self.messages.append($0) })
    }

    func records() throws -> [PhotoRecord] {
        try PhotoInventory(destination: destination, readOnly: true).records()
    }

    func target(_ record: PhotoRecord) -> URL { destination.appendingPathComponent(record.relativePath) }
}

@Test
func cardInventorySkipsDeletedAndRestoresOnlyWhenEnabled() throws {
    let f = try CardFixture()
    let original = try f.write()
    #expect(f.run() == 0)
    let record = try #require(f.records().first)
    #expect(record.complete)
    #expect(record.deviceID == "card:\(f.source.id)")
    #expect(try Data(contentsOf: f.target(record)) == Data(contentsOf: original))
    #expect(f.run() == 0)
    #expect(try f.records().count == 1)
    #expect(f.messages.contains { $0.contains("already imported from this card") })
    try FileManager.default.removeItem(at: f.target(record))
    f.settings.overwrite = true
    #expect(f.run() == 0)
    #expect(!FileManager.default.fileExists(atPath: f.target(record).path))
    #expect(f.messages.contains { $0.contains("deleted locally") })
    f.settings.redownloadDeletedFiles = true
    #expect(f.run() == 0)
    #expect(try Data(contentsOf: f.target(record)) == Data(contentsOf: original))
    #expect(try f.records().count == 1)
}

@Test
func separateCardsNeverOverwriteEachOthersPhotos() throws {
    let f = try CardFixture()
    let original = try f.write()
    #expect(f.run() == 0)
    let first = try #require(f.records().first)
    // The same card filename on a separately configured source must retain its own copy.
    f.source.id = UUID().uuidString
    f.settings.overwrite = true
    #expect(f.run() == 0)
    let records = try f.records()
    #expect(records.count == 2)
    #expect(Set(records.map(\.relativePath)).count == 2)
    #expect(try Data(contentsOf: f.target(first)) == Data(contentsOf: original))
    #expect(records.allSatisfy { $0.complete })
}

@Test
func cardDryRunDoesNotCreateOrModifyInventory() throws {
    let f = try CardFixture()
    try f.write()
    f.settings.dryRun = true
    #expect(f.run() == 0)
    #expect(!FileManager.default.fileExists(atPath: f.destination.path))
    f.settings.dryRun = false
    #expect(f.run() == 0)
    let database = f.destination.appendingPathComponent(".iphone-import.sqlite3")
    let before = try Data(contentsOf: database)
    try f.write("DCIM/IMG_0002.JPG")
    f.settings.dryRun = true
    #expect(f.run() == 0)
    #expect(try Data(contentsOf: database) == before)
    #expect(try f.records().count == 1)
}

@Test
func cancelledCardCopyRetriesIncompleteInventoryEntry() throws {
    let f = try CardFixture()
    try f.write()
    var checks = 0
    #expect(f.run(isCancelled: { checks += 1; return checks > 2 }) == 1)
    let incomplete = try #require(f.records().first)
    #expect(!incomplete.complete)
    #expect(!FileManager.default.fileExists(atPath: f.target(incomplete).path))
    #expect(f.run() == 0)
    let completed = try #require(f.records().first)
    #expect(completed.complete)
    #expect(completed.relativePath == incomplete.relativePath)
    #expect(FileManager.default.fileExists(atPath: f.target(completed).path))
}

@Test
func updatingCardLocationKeepsItsHistory() throws {
    let f = try CardFixture()
    try f.write()
    #expect(f.run() == 0)
    let record = try #require(f.records().first)
    try FileManager.default.removeItem(at: f.target(record))
    let renamed = f.root.appendingPathComponent("renamed-card")
    try FileManager.default.moveItem(atPath: f.source.location, toPath: renamed.path)
    f.source.location = renamed.path
    #expect(f.run() == 0)
    #expect(try f.records().count == 1)
    #expect(!FileManager.default.fileExists(atPath: f.target(record).path))
}

@Test
func cardAdoptionRegistersExistingFiles() throws {
    let f = try CardFixture()
    let original = try f.write()
    let date = try #require(original.resourceValues(forKeys: [.creationDateKey]).creationDate)
    let target = try f.job.importerOptions().target(name: original.lastPathComponent, date: date)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: original, to: target)
    f.settings.adoptExisting = true
    #expect(f.run() == 0)
    let record = try #require(f.records().first)
    #expect(record.complete)
    #expect(f.target(record) == target)
    #expect(f.messages.contains { $0.contains("Adopted") })
    try FileManager.default.removeItem(at: target)
    #expect(f.run() == 0)
    #expect(!FileManager.default.fileExists(atPath: target.path))
}

@Test(arguments: [false, true])
func cardSameNameFilesAreComparedByContent(identical: Bool) throws {
    let f = try CardFixture()
    try f.write("DCIM/a/IMG_0001.JPG")
    try f.write("DCIM/b/IMG_0001.JPG", bytes: identical ? [1, 2, 3, 4] : [4, 3, 2, 1])
    #expect(f.run() == 0)
    let records = try f.records()
    #expect(records.count == (identical ? 1 : 2))
    #expect(records.reduce(0) { $0 + $1.aliases.count } == (identical ? 1 : 0))
    #expect(f.run() == 0)
    #expect(try f.records().count == records.count)
}

@Test
func cardMarkerRoundTripAndNoOverwrite() throws {
    let f = try CardFixture()
    let folder = URL(fileURLWithPath: f.source.location)
    #expect(try CardIdentity.read(from: folder) == nil)
    try CardIdentity.create(for: folder, uuid: f.source.id)
    #expect(try CardIdentity.read(from: folder) == f.source.id)
    #expect(CardIdentity.markerURL(for: folder).deletingLastPathComponent() == folder.deletingLastPathComponent())
    #expect(throws: (any Error).self) {
        try CardIdentity.create(for: folder, uuid: UUID().uuidString)
    }
    #expect(try CardIdentity.read(from: folder) == f.source.id)
}

@Test
func markedCardPreservesLegacyHistoryAndRejectsReplacement() throws {
    let f = try CardFixture()
    _ = try f.write()
    #expect(f.run() == 0)
    let folder = URL(fileURLWithPath: f.source.location)
    try CardIdentity.create(for: folder, uuid: f.source.id)
    f.source.cardUUID = f.source.id
    #expect(f.run() == 0)
    #expect(f.messages.contains { $0.contains("already imported from this card") })
    try FileManager.default.removeItem(at: CardIdentity.markerURL(for: folder))
    #expect(f.run() == 1)
    #expect(try f.records().count == 1)
    try CardIdentity.create(for: folder, uuid: UUID().uuidString)
    #expect(f.run() == 1)
}

@Test
func cardMarkerRejectsMalformedAndSymlinkedFiles() throws {
    let f = try CardFixture()
    let folder = URL(fileURLWithPath: f.source.location)
    let marker = CardIdentity.markerURL(for: folder)
    try Data("not-a-uuid".utf8).write(to: marker)
    #expect(throws: (any Error).self) { try CardIdentity.read(from: folder) }
    try FileManager.default.removeItem(at: marker)
    let other = f.root.appendingPathComponent("other.txt")
    try Data(UUID().uuidString.utf8).write(to: other)
    try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: other)
    #expect(throws: (any Error).self) { try CardIdentity.read(from: folder) }
}

@Test
func markerIdentitySurvivesNewRowAndObsoleteRowCannotImport() throws {
    let f = try CardFixture()
    _ = try f.write()
    let folder = URL(fileURLWithPath: f.source.location)
    try CardIdentity.create(for: folder, uuid: f.source.id)
    f.source.cardUUID = f.source.id
    #expect(f.run() == 0)
    f.source.id = UUID().uuidString
    #expect(f.run() == 0)
    #expect(f.messages.contains { $0.contains("already imported from this card") })
    f.source.obsolete = true
    #expect(f.run() == 1)
}

@Test
func legacySourceDecodesWithoutCardFields() throws {
    let data = Data(#"{"id":"old","kind":"card","label":"Card","location":"/Volumes/Card/DCIM","overrides":{}}"#.utf8)
    let source = try JSONDecoder().decode(ImportSource.self, from: data)
    #expect(source.cardUUID == nil)
    #expect(source.obsolete == nil)
}

@Test
func restoredMarkerRetainsHistoryWhenUUIDDiffersFromRowID() throws {
    let f = try CardFixture()
    _ = try f.write()
    let folder = URL(fileURLWithPath: f.source.location)
    let retainedUUID = UUID().uuidString
    f.source.cardUUID = retainedUUID
    try CardIdentity.create(for: folder, uuid: retainedUUID)
    #expect(f.run() == 0)
    try FileManager.default.removeItem(at: CardIdentity.markerURL(for: folder))
    #expect(f.run() == 1)
    var job = f.job
    job.allowMissingCardMarker = true
    var messages: [String] = []
    #expect(CardImporter.run(job: job, isCancelled: { false }, log: { messages.append($0) }) == 0)
    #expect(messages.contains { $0.contains("already imported from this card") })
    #expect(try f.records().count == 1)
    // The exception is per job, not stored in the source or inventory.
    #expect(f.run() == 1)
    try CardIdentity.create(for: folder, uuid: retainedUUID)
    #expect(f.run() == 0)
    #expect(f.messages.contains { $0.contains("already imported from this card") })
    #expect(try f.records().first?.deviceID == "card:\(retainedUUID)")
    try FileManager.default.removeItem(at: CardIdentity.markerURL(for: folder))
    try CardIdentity.create(for: folder, uuid: UUID().uuidString)
    #expect(CardImporter.run(job: job, isCancelled: { false }, log: { _ in }) == 1)
}
