import Photos
import SwiftUI

@MainActor
final class CompanionModel: ObservableObject {
    @Published var status = "Starting…"
    @Published var access = "Photos access: not requested"
    @Published var log: [String] = []
    private var server: CompanionServer?

    func start() async {
        UIApplication.shared.isIdleTimerDisabled = true
        let status = await PhotoLibrary.requestAccess()
        access = status == .authorized
            ? "Photos access: full"
            : "Photos access: \(status == .limited ? "limited" : "denied") — choose Full Access in Settings → Photos"
        let server = CompanionServer { [weak self] message in
            DispatchQueue.main.async { self?.append(message) }
        }
        do {
            try server.start()
            self.server = server
            self.status = "Ready. Run the Mac importer with --companion over USB and keep this app open."
        } catch {
            self.status = error.localizedDescription
        }
    }

    private func append(_ message: String) {
        log.append(message)
        if log.count > 50 { log.removeFirst(log.count - 50) }
    }
}

@main
struct PhotoImportCompanionApp: App {
    @StateObject private var model = CompanionModel()

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Photo Import Companion").font(.title2.bold())
                Text(model.status)
                Text(model.access).font(.footnote)
                List(Array(model.log.enumerated()), id: \.offset) { Text($0.element).font(.caption.monospaced()) }
            }
            .padding()
            .task { await model.start() }
        }
    }
}
