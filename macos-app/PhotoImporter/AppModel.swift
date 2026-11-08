import AppKit
import SwiftUI

enum ActiveSheet: Identifiable {
    case destinationSettings
    case sourceSettings(String)
    case newDestination(URL)
    case addPhone(replacing: String?)
    case importing(ImportSource, ImportMode)
    case lightroom

    var id: String {
        switch self {
        case .destinationSettings: return "destinationSettings"
        case .sourceSettings(let id): return "sourceSettings-\(id)"
        case .newDestination: return "newDestination"
        case .addPhone: return "addPhone"
        case .importing(let source, _): return "importing-\(source.id)"
        case .lightroom: return "lightroom"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    private static let destinationKey = "importDestination"

    @Published private(set) var destination: URL?
    @Published var settings = ImportSettings()
    @Published var sources: [ImportSource] = []
    @Published var activeSheet: ActiveSheet?
    @Published var errorMessage: String?

    let runner = ImportRunner()
    let detector = PhoneDetector()
    private var store: DestinationStore?

    init() {
        if let path = UserDefaults.standard.string(forKey: Self.destinationKey) {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if DestinationStore.databaseExists(in: url) { open(url, createIfMissing: false, keepSources: false) }
        }
        detector.start()
    }

    var cards: [ImportSource] { sources.filter { $0.kind == .card } }
    var phones: [ImportSource] { sources.filter { $0.kind == .phone } }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder that will receive the date folders"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let existing = try? DestinationStore(destination: url), DestinationStore.databaseExists(in: url), existing.hasSettings {
            open(url, createIfMissing: false, keepSources: false)
        } else {
            activeSheet = .newDestination(url)
        }
    }

    var canKeepPreviousSources: Bool { store != nil }

    func createDestination(_ url: URL, keepSources: Bool) {
        open(url, createIfMissing: true, keepSources: keepSources)
    }

    private func open(_ url: URL, createIfMissing: Bool, keepSources: Bool) {
        do {
            let next = try DestinationStore(destination: url)
            if createIfMissing { try next.createSettings(copyingFrom: keepSources ? store : nil) }
            guard next.hasSettings else { return }
            settings = try next.loadSettings()
            sources = try next.loadSources()
            store = next
            destination = url
            UserDefaults.standard.set(url.path, forKey: Self.destinationKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveSettings() { persist { try $0.saveSettings(settings) } }
    func saveSources() { persist { try $0.saveSources(sources) } }

    private func persist(_ work: (DestinationStore) throws -> Void) {
        guard let store else { return }
        do { try work(store) } catch { errorMessage = error.localizedDescription }
    }

    func source(id: String) -> ImportSource? { sources.first { $0.id == id } }

    func update(_ source: ImportSource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index] = source
        saveSources()
    }

    func add(_ source: ImportSource) {
        sources.append(source)
        saveSources()
    }

    // Removes only the row and its settings, never any photos or the import inventory.
    func delete(_ source: ImportSource) {
        sources.removeAll { $0.id == source.id }
        saveSources()
    }

    func chooseCardFolder(replacing existing: ImportSource? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = URL(fileURLWithPath: existing?.location ?? "/Volumes")
        panel.prompt = "Choose"
        panel.message = "Choose the memory card folder (for example DCIM)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if var existing {
            existing.location = url.path
            update(existing)
        } else {
            add(ImportSource(kind: .card, label: url.pathComponents.dropFirst(2).first ?? url.lastPathComponent,
                             location: url.path))
        }
    }

    func show(_ source: ImportSource) {
        NSWorkspace.shared.open(URL(fileURLWithPath: source.location))
    }

    func beginImport(_ source: ImportSource, mode: ImportMode) {
        guard let destination else { return }
        if mode != .card { detector.stop() }
        activeSheet = .importing(source, mode)
        runner.start(ImportJob(source: source, mode: mode, destination: destination,
                               settings: source.effectiveSettings(settings)))
    }

    func finishImport() {
        activeSheet = nil
        detector.start()
    }
}
