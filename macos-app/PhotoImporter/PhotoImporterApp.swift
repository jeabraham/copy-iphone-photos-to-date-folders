import SwiftUI

@main
struct PhotoImporterApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 780, minHeight: 640)
        }
    }
}
