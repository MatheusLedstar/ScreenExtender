import SwiftUI
import AppKit

@main
struct ScreenExtenderApp: App {
    init() {
        // Required for SPM-based SwiftUI apps to show window and accept input
        NSApp.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
