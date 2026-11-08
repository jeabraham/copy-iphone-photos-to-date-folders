import SwiftUI

struct ImportSheet: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var runner: ImportRunner
    let source: ImportSource
    let mode: ImportMode

    private var title: String {
        switch mode {
        case .card: return "Importing from \(source.label)"
        case .phoneDirect: return "Importing from \(source.label) directly"
        case .phoneViaApp: return "Importing from \(source.label) via the companion app"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(runner.lines.enumerated()), id: \.offset) { index, line in
                            Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).id(index)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .border(Color.secondary.opacity(0.4))
                .onChange(of: runner.lines.count) { _, count in
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
            if let code = runner.exitCode {
                if code == 0 {
                    Label("Finished.", systemImage: "checkmark.circle").foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Finished with problems. See the messages above.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        if mode != .card { Text(PhoneGuidance.shortChecklist).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            HStack {
                Spacer()
                Button(runner.isCancelling ? "Cancelling…" : "Cancel") { runner.cancel() }
                    .disabled(!runner.isRunning || runner.isCancelling)
                Button("Done") { model.finishImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(runner.isRunning)
            }
        }
        .padding(20)
        .frame(width: 720, height: 460)
        .interactiveDismissDisabled()
    }
}

struct LightroomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next steps in Lightroom Classic").font(.title3)
            Text("1. File > Import Photos and Video…")
            Text("2. Under Source, choose this folder:")
            Text(model.destination?.path ?? "(choose a destination first)")
                .font(.system(.body, design: .monospaced)).textSelection(.enabled).padding(.leading, 16)
            Text("3. Tick “Include Subfolders” and choose “Add” at the top (do not Copy or Move).")
            Text("4. Tick “Don’t Import Suspected Duplicates”, then click Import.")
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
