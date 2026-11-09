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
    private var confirmedMissingCardMarker = false

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

    private func choice(_ title: String, _ message: String, buttons: [String]) -> Int {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for button in buttons { alert.addButton(withTitle: button) }
        return alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }

    private func nameCard(suggested: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Name this camera card"
        alert.informativeText = "Choose a name you can recognize, such as Egypt Card #1. Consider writing the same name on the physical card. For a newly formatted card, use a new name such as Egypt Card #1 — November reuse. You can rename it later in Settings without changing its import history."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.stringValue = suggested
        field.placeholderString = "Egypt Card #1"
        field.setAccessibilityLabel("Card name")
        alert.accessoryView = field
        alert.addButton(withTitle: "Save Name")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        while alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
            alert.messageText = "Please enter a card name"
        }
        return nil
    }

    func chooseCardFolder(replacing existing: ImportSource? = nil) {
        guard !runner.isRunning else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = URL(fileURLWithPath: existing?.location ?? "/Volumes")
        panel.message = "Choose the card's DCIM folder (all subfolders are included)"
        panel.prompt = "Choose"
        while panel.runModal() == .OK, let url = panel.url {
            if url.lastPathComponent.caseInsensitiveCompare("DCIM") != .orderedSame {
                let answer = choice("This folder is not called DCIM",
                                    "Choose the camera's DCIM folder to keep photo paths consistent. If you use this folder, the card identifier will be written in its parent folder: \(url.deletingLastPathComponent().path)",
                                    buttons: ["Choose Another Folder", "Use This Folder", "Cancel"])
                if answer == 0 { continue }
                if answer != 1 { return }
            }
            let proposed = existing ?? ImportSource(kind: .card,
                label: url.deletingLastPathComponent().lastPathComponent, location: url.path)
            _ = prepareCard(proposed, folder: url, isNew: existing == nil)
            return
        }
    }

    // Resolve identity before saving the row or starting any photo transfer.
    private func prepareCard(_ original: ImportSource, folder: URL, isNew: Bool = false) -> ImportSource? {
        confirmedMissingCardMarker = false
        var continueWithoutMarker = false
        let folder = folder.standardizedFileURL.resolvingSymlinksInPath()
        do {
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &directory), directory.boolValue else {
                throw ImportError(message: "Card folder is not available: \(folder.path)")
            }
            let found = try CardIdentity.read(from: folder)
            var selected = original
            var replaced = false
            if let found, let known = sources.first(where: {
                $0.kind == .card && ($0.cardUUID == found || $0.id == found)
            }), known.id != original.id {
                guard choice("This is a different saved card",
                             "The identifier belongs to “\(known.label)”. Use that card's row and import history at this location?",
                             buttons: ["Use Recognized Card", "Cancel"]) == 0 else { return nil }
                selected = known
                replaced = !isNew
            } else if original.cardUUID != nil && found == nil {
                let answer = choice("Missing identifier for “\(original.label)”",
                                    "If you accidentally deleted the marker and this is the same, unformatted card, retain its history and restore the saved identifier. If the card was formatted or replaced, create a new identity instead.",
                                    buttons: ["Same Card — Retain History", "New Card", "Cancel"])
                if answer == 1 {
                    selected.id = UUID().uuidString
                    selected.cardUUID = nil
                    selected.label += " (new card)"
                    replaced = true
                } else if answer != 0 { return nil }
            } else if (original.cardUUID != nil && found != original.cardUUID)
                        || (found != nil && found != original.id && original.cardUUID == nil && !isNew) {
                guard choice("Card replaced or formatted",
                             "The expected identifier for “\(original.label)” is missing or different. The same folder path does not establish that this is the same card. Create a new row with separate import history? The old row and its history will be kept.",
                             buttons: ["Create New Card Row", "Cancel"]) == 0 else { return nil }
                selected.id = UUID().uuidString
                selected.cardUUID = nil
                selected.label += " (new card)"
                replaced = true
            } else if found == nil && original.cardUUID == nil && !isNew {
                let answer = choice("Confirm this unmarked card",
                                    "This row has no verified card identifier. Is this the same, unformatted card previously used for “\(original.label)”? Choose New Card if it has been replaced or formatted. A visible identifier file will be created beside the selected folder if possible.",
                                    buttons: ["Same Card", "New Card", "Cancel"])
                if answer == 1 {
                    selected.id = UUID().uuidString
                    selected.label += " (new card)"
                    replaced = true
                } else if answer != 0 { return nil }
            }
            if !sources.contains(where: { $0.id == selected.id }) {
                guard let name = nameCard(suggested: selected.label) else { return nil }
                selected.label = name
            }
            selected.location = folder.path
            selected.obsolete = false
            if let found {
                selected.cardUUID = found
            } else {
                do {
                    let retainedUUID = selected.cardUUID ?? selected.id
                    try CardIdentity.create(for: folder, uuid: retainedUUID)
                    selected.cardUUID = retainedUUID
                } catch {
                    // A newly appeared or malformed marker must not become an unverified fallback.
                    guard try CardIdentity.read(from: folder) == nil else { throw error }
                    guard choice("Cannot write the card identifier",
                                 "\(error.localizedDescription)\n\nContinue without a marker? You will need to confirm the card's identity each time. A volume name or folder path cannot distinguish a formatted or replacement card.",
                                 buttons: ["Continue Without Marker", "Cancel"]) == 0 else { return nil }
                    // Keep the historical UUID even when the physical marker cannot be restored.
                    // Permission to import without it applies only to this invocation.
                    continueWithoutMarker = true
                }
            }
            var next = sources
            if replaced && choice("Mark the old location obsolete?",
                                  "Keep “\(original.label)” and its import history, but disable importing from its old location? You can reactivate it later with Update location.",
                                  buttons: ["Mark Obsolete", "Keep Active"]) == 0,
               let index = next.firstIndex(where: { $0.id == original.id }) {
                next[index].obsolete = true
            }
            if let index = next.firstIndex(where: { $0.id == selected.id }) {
                next[index] = selected
            } else {
                next.append(selected)
            }
            // Do not start an import if saving the verified identity fails.
            guard let store else { return nil }
            try store.saveSources(next)
            sources = next
            confirmedMissingCardMarker = continueWithoutMarker
            return selected
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func show(_ source: ImportSource) {
        NSWorkspace.shared.open(URL(fileURLWithPath: source.location))
    }

    func beginImport(_ source: ImportSource, mode: ImportMode) {
        guard let destination, !runner.isRunning else { return }
        var source = source
        if case .card = mode {
            guard source.obsolete != true,
                  let verified = prepareCard(source, folder: URL(fileURLWithPath: source.location)) else { return }
            source = verified
        }
        activeSheet = .importing(source, mode)
        runner.start(ImportJob(source: source, mode: mode, destination: destination,
                               settings: source.effectiveSettings(settings),
                               allowMissingCardMarker: confirmedMissingCardMarker), detector: detector)
    }

    func finishImport() {
        activeSheet = nil
        detector.start()
    }
}
