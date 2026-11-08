import SwiftUI

@main
struct PhotoImporterApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 780, minHeight: 640)
                .navigationTitle("Photo Copier - Date Folders")
        }
        Window("Photo Copier - Date Folders Help", id: "help") {
            HelpView()
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button("Photo Copier - Date Folders Help") { openWindow(id: "help") }
                    .keyboardShortcut("?")
            }
        }
    }
}
