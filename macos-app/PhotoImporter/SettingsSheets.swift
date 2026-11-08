import SwiftUI

struct DestinationSettingsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Destination import settings").font(.title3)
            Text("Defaults for every source. Each memory card or iPhone can override them.")
                .foregroundStyle(.secondary)
            Toggle("Include videos", isOn: $model.settings.includeVideos)
            Toggle("Overwrite existing files", isOn: $model.settings.overwrite)
            Toggle("Redownload deleted photos", isOn: $model.settings.redownloadDeletedFiles)
            Text("When off, previously imported card and iPhone files stay deleted, even when overwrite is on.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Dry run (list what would be copied)", isOn: $model.settings.dryRun)
            Toggle("Adopt matching files already in the destination", isOn: $model.settings.adoptExisting)
                .disabled(model.settings.overwrite)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: model.settings) { _, _ in model.saveSettings() }
    }
}

private struct TriStatePicker: View {
    let title: String
    @Binding var value: Bool?

    var body: some View {
        Picker(title, selection: $value) {
            Text("Use destination setting").tag(Bool?.none)
            Text("Yes").tag(Bool?.some(true))
            Text("No").tag(Bool?.some(false))
        }
    }
}

struct SourceSettingsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let sourceID: String
    @State private var source: ImportSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if source != nil {
                Text("Settings for \(source!.label)").font(.title3)
                TextField("Name", text: Binding(get: { source!.label }, set: { source!.label = $0 }))
                TriStatePicker(title: "Include videos", value: Binding(
                    get: { source!.overrides.includeVideos }, set: { source!.overrides.includeVideos = $0 }))
                TriStatePicker(title: "Overwrite", value: Binding(
                    get: { source!.overrides.overwrite }, set: { source!.overrides.overwrite = $0 }))
                TriStatePicker(title: "Dry run", value: Binding(
                    get: { source!.overrides.dryRun }, set: { source!.overrides.dryRun = $0 }))
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    if let source { model.update(source) }
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { source = model.source(id: sourceID) }
    }
}

struct NewDestinationSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var keepSources = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New import destination").font(.title3)
            Text("“\(url.lastPathComponent)” has no import settings yet. Create them?")
            if model.canKeepPreviousSources {
                Toggle("Keep the memory cards, iPhones and settings from the current destination", isOn: $keepSources)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create settings") {
                    dismiss()
                    model.createDestination(url, keepSources: keepSources && model.canKeepPreviousSources)
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

struct AddPhoneSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let replacingID: String?
    @State private var label = ""
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(replacingID == nil ? "Add an iPhone" : "Update iPhone").font(.title3)
            Text("Connect the iPhone to this Mac and get it ready:")
            ForEach(Array(PhoneGuidance.steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)").font(.callout)
            }
            PhoneChoices(detector: model.detector, selected: $selected, onChoose: choose)
            if selected == nil && !model.detector.phones.isEmpty {
                Text("Click a detected phone above to select it.").font(.caption).foregroundStyle(.secondary)
            }
            TextField("Name for this phone, e.g. John’s iPhone", text: $label)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(replacingID == nil ? "Add" : "Update") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil || label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onReceive(model.detector.$phones) { phones in
            // With exactly one phone attached there is nothing to choose.
            if selected == nil, phones.count == 1 { choose(phones[0]) }
        }
        .onAppear {
            if let id = replacingID, let source = model.source(id: id) {
                label = source.label
                selected = source.location
            }
        }
    }

    private func choose(_ phone: DetectedPhone) {
        selected = phone.name
        if label.trimmingCharacters(in: .whitespaces).isEmpty { label = phone.name }
    }

    private func save() {
        guard let selected else { return }
        let name = label.trimmingCharacters(in: .whitespaces)
        if let id = replacingID, var source = model.source(id: id) {
            source.label = name
            source.location = selected
            model.update(source)
        } else {
            model.add(ImportSource(kind: .phone, label: name, location: selected))
        }
        dismiss()
    }
}

private struct PhoneChoices: View {
    @ObservedObject var detector: PhoneDetector
    @Binding var selected: String?
    let onChoose: (DetectedPhone) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            if detector.phones.isEmpty {
                Label("Waiting for an iPhone… nothing detected yet.", systemImage: "iphone.slash")
                    .foregroundStyle(.orange)
            }
            ForEach(detector.phones) { phone in
                Button {
                    onChoose(phone)
                } label: {
                    Label(phone.name, systemImage: selected == phone.name ? "checkmark.circle.fill" : "iphone")
                }
                .buttonStyle(.plain)
            }
        }
    }
}
