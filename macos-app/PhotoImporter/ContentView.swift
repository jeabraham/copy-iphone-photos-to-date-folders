import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DestinationSection()
            if model.destination != nil {
                CardsSection()
                PhonesSection()
            } else {
                Text("Choose an import destination to begin.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Next steps in Lightroom") { model.activeSheet = .lightroom }
            }
        }
        .padding(20)
        .sheet(item: $model.activeSheet) { sheet in
            switch sheet {
            case .destinationSettings: DestinationSettingsSheet()
            case .sourceSettings(let id): SourceSettingsSheet(sourceID: id)
            case .newDestination(let url): NewDestinationSheet(url: url)
            case .addPhone(let replacing): AddPhoneSheet(replacingID: replacing)
            case .importing(let source, let mode): ImportSheet(runner: model.runner, source: source, mode: mode)
            case .lightroom: LightroomSheet()
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct DestinationSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GroupBox("Import destination") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.destination?.path ?? "No folder chosen")
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(model.destination == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose…") { model.chooseDestination() }
                    Button("Settings") { model.activeSheet = .destinationSettings }
                        .disabled(model.destination == nil)
                }
                if model.destination != nil {
                    DateRangeEditor()
                }
            }
            .padding(6)
        }
    }
}

struct DateRangeEditor: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 24) {
            OptionalDateField(title: "From", text: $model.settings.fromDate)
            OptionalDateField(title: "To", text: $model.settings.toDate)
            Spacer()
        }
        .font(.headline)
        .onChange(of: model.settings) { _, _ in model.saveSettings() }
    }
}

struct OptionalDateField: View {
    let title: String
    @Binding var text: String?

    private static let formatter = Options.dateFormatter()

    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(get: { text != nil }, set: { text = $0 ? Self.formatter.string(from: Date()) : nil }))
            if text != nil {
                DatePicker("", selection: Binding(
                    get: { text.flatMap(Self.formatter.date(from:)) ?? Date() },
                    set: { text = Self.formatter.string(from: $0) }), displayedComponents: .date)
                    .labelsHidden()
            } else {
                Text("any").foregroundStyle(.secondary).font(.body)
            }
        }
    }
}

struct CardsSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if model.cards.isEmpty {
                    Text("Add a memory card with +. Insert the card, then press Import.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.cards) { CardRow(source: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            HStack {
                Text("Memory cards")
                Button { model.chooseCardFolder() } label: { Image(systemName: "plus") }
            }
        }
    }
}

struct CardRow: View {
    @EnvironmentObject var model: AppModel
    let source: ImportSource

    private var isMounted: Bool { FileManager.default.fileExists(atPath: source.location) }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(source.label).font(.headline)
                Text(isMounted ? source.location : "Not found: \(source.location). Insert the card or use Update location.")
                    .font(.caption).foregroundStyle(isMounted ? Color.secondary : Color.red)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Settings") { model.activeSheet = .sourceSettings(source.id) }
            Button("Show") { model.show(source) }.disabled(!isMounted)
            Button("Update location") { model.chooseCardFolder(replacing: source) }
            Button("Import") { model.beginImport(source, mode: .card) }.disabled(!isMounted)
            Button("Delete", role: .destructive) { model.delete(source) }
        }
    }
}

struct PhonesSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if model.phones.isEmpty {
                    Text("Add an iPhone with +. You will be asked to connect it by USB.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.phones) { PhoneRow(detector: model.detector, source: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            HStack {
                Text("iPhones")
                Button { model.activeSheet = .addPhone(replacing: nil) } label: { Image(systemName: "plus") }
            }
        }
    }
}

struct PhoneRow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var detector: PhoneDetector
    let source: ImportSource

    private var connected: Bool { detector.isConnected(name: source.location) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading) {
                    Text(source.label).font(.headline)
                    Text(connected ? "Connected and ready" : "Not detected")
                        .font(.caption).foregroundStyle(connected ? Color.green : Color.orange)
                }
                Spacer()
                Button("Settings") { model.activeSheet = .sourceSettings(source.id) }
                Button("Update") { model.activeSheet = .addPhone(replacing: source.id) }
                Button("Import directly") { model.beginImport(source, mode: .phoneDirect) }
                Button("Import via app") { model.beginImport(source, mode: .phoneViaApp) }
                Button("Delete", role: .destructive) { model.delete(source) }
            }
            if !connected {
                Text(PhoneGuidance.shortChecklist).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

enum PhoneGuidance {
    static let shortChecklist = "Connect by USB, unlock the phone and tap Trust. Close Lightroom, Image Capture and Photos import windows. For “Import via app”, keep the Photo Import Companion app open on the phone."

    static let steps = [
        "Unplug any other phone or camera from the Mac.",
        "Plug in the iPhone with a data-capable USB cable.",
        "Unlock the iPhone and tap Trust if asked.",
        "Close Lightroom Classic, Image Capture and Photos, or any import window they opened.",
        "To import via the companion app, open Photo Import Companion on the phone, leave it in front, and allow Full Access to Photos there.",
    ]
}
