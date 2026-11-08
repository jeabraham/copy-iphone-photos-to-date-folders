import Foundation
import SQLite3

// App settings live in the destination's importer database (.iphone-import.sqlite3) in their own
// tables. The importer's schema (PRAGMA user_version) is never touched here.
final class DestinationStore {
    static let databaseName = ".iphone-import.sqlite3"
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    let destination: URL
    private var handle: OpaquePointer?

    static func databaseExists(in destination: URL) -> Bool {
        FileManager.default.fileExists(atPath: destination.appendingPathComponent(databaseName).path)
    }

    init(destination: URL) throws {
        self.destination = destination
        let path = destination.appendingPathComponent(Self.databaseName).path
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw ImportError(message: "Cannot open settings database in \(destination.path)")
        }
        sqlite3_busy_timeout(handle, 5000)
    }

    deinit { sqlite3_close(handle) }

    var hasSettings: Bool {
        guard let rows = try? query("SELECT name FROM sqlite_master WHERE type='table' AND name='app_settings'") else { return false }
        return !rows.isEmpty
    }

    // Creates the importer's own tables first (through the shared importer code) so a later
    // dry run against this database does not see an empty, unversioned file.
    func createSettings(copyingFrom other: DestinationStore?) throws {
        _ = try PhotoInventory(destination: destination, readOnly: false)
        try execute("CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        try execute("""
            CREATE TABLE IF NOT EXISTS app_sources (
                id TEXT PRIMARY KEY, position INTEGER NOT NULL, json TEXT NOT NULL)
            """)
        if let other {
            try saveSettings(try other.loadSettings())
            try saveSources(try other.loadSources())
        } else {
            try saveSettings(ImportSettings())
        }
    }

    func loadSettings() throws -> ImportSettings {
        let rows = try query("SELECT value FROM app_settings WHERE key = 'import'")
        guard let json = rows.first?.first, let data = json.data(using: .utf8) else { return ImportSettings() }
        return try JSONDecoder().decode(ImportSettings.self, from: data)
    }

    func saveSettings(_ settings: ImportSettings) throws {
        let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        try execute("INSERT OR REPLACE INTO app_settings (key, value) VALUES ('import', ?)", [json])
    }

    func loadSources() throws -> [ImportSource] {
        try query("SELECT json FROM app_sources ORDER BY position").compactMap { row in
            row.first?.data(using: .utf8).flatMap { try? JSONDecoder().decode(ImportSource.self, from: $0) }
        }
    }

    func saveSources(_ sources: [ImportSource]) throws {
        try execute("BEGIN")
        do {
            try execute("DELETE FROM app_sources")
            for (index, source) in sources.enumerated() {
                let json = String(decoding: try JSONEncoder().encode(source), as: UTF8.self)
                try execute("INSERT INTO app_sources (id, position, json) VALUES (?, ?, ?)",
                            [source.id, String(index), json])
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    @discardableResult
    private func query(_ sql: String, _ values: [String] = []) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, Self.transient)
        }
        var rows: [[String]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw databaseError() }
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
            })
        }
    }

    private func execute(_ sql: String, _ values: [String] = []) throws {
        try query(sql, values)
    }

    private func databaseError() -> ImportError {
        ImportError(message: "Settings database error: \(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "not open")")
    }
}
