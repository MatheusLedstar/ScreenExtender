import SwiftUI
import AppKit
import Foundation

// Check for --test flag before SwiftUI launches
// Must be a top-level check since @main takes over
private let isTestMode = CommandLine.arguments.contains("--test")

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if isTestMode {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await VirtualDisplayTest.run()
                exit(0)
            }
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct ScreenExtenderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
