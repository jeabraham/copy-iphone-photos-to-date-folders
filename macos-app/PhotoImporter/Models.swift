import Foundation

struct ImportSettings: Codable, Equatable {
    var includeVideos = false
    var overwrite = false
    var dryRun = false
    var adoptExisting = true
    var redownloadDeletedFiles = false
    // Inclusive local dates as yyyy-MM-dd.
    var fromDate: String?
    var toDate: String?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case includeVideos, overwrite, dryRun, adoptExisting, redownloadDeletedFiles, fromDate, toDate
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        includeVideos = try values.decodeIfPresent(Bool.self, forKey: .includeVideos) ?? false
        overwrite = try values.decodeIfPresent(Bool.self, forKey: .overwrite) ?? false
        dryRun = try values.decodeIfPresent(Bool.self, forKey: .dryRun) ?? false
        adoptExisting = try values.decodeIfPresent(Bool.self, forKey: .adoptExisting) ?? true
        redownloadDeletedFiles = try values.decodeIfPresent(Bool.self, forKey: .redownloadDeletedFiles) ?? false
        fromDate = try values.decodeIfPresent(String.self, forKey: .fromDate)
        toDate = try values.decodeIfPresent(String.self, forKey: .toDate)
    }
}

struct SourceOverrides: Codable, Equatable {
    var includeVideos: Bool?
    var overwrite: Bool?
    var dryRun: Bool?
}

enum SourceKind: String, Codable {
    case card, phone
}

struct ImportSource: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var kind: SourceKind
    // User-visible name, e.g. "John's iPhone".
    var label: String
    // Card: folder path. Phone: the device name reported by ImageCaptureCore.
    var location: String
    var overrides = SourceOverrides()

    func effectiveSettings(_ base: ImportSettings) -> ImportSettings {
        var settings = base
        if let value = overrides.includeVideos { settings.includeVideos = value }
        if let value = overrides.overwrite { settings.overwrite = value }
        if let value = overrides.dryRun { settings.dryRun = value }
        return settings
    }
}

enum ImportMode {
    case card
    case phoneDirect
    case phoneViaApp
}

struct ImportJob {
    let source: ImportSource
    let mode: ImportMode
    let destination: URL
    let settings: ImportSettings

    // Maps the app's settings onto the importer's options, validating the date range like the CLI does.
    func importerOptions() throws -> Options {
        var options = Options()
        options.destination = destination.standardizedFileURL
        options.excludeMovies = !settings.includeVideos
        options.overwrite = settings.overwrite
        options.adoptExisting = settings.adoptExisting && !settings.overwrite
        options.dryRun = settings.dryRun
        options.redownloadDeletedFiles = settings.redownloadDeletedFiles
        options.companion = mode == .phoneViaApp
        if mode == .phoneDirect { options.deviceName = source.location }
        let formatter = Options.dateFormatter()
        if let text = settings.fromDate {
            guard let date = formatter.date(from: text) else { throw ImportError(message: "Invalid from date: \(text)") }
            options.start = date
        }
        if let text = settings.toDate {
            guard let date = formatter.date(from: text),
                  let next = Calendar.current.date(byAdding: .day, value: 1, to: date) else {
                throw ImportError(message: "Invalid to date: \(text)")
            }
            options.end = next
        }
        if let start = options.start, let end = options.end, start >= end {
            throw ImportError(message: "The from date must not be later than the to date.")
        }
        return options
    }
}
