import SwiftUI
import AppKit

/// Keeps the process alive when the only window is closed, so playback continues
/// in the background and the window can be reopened from the Dock.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct YT_MusicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // App-level state lives for the whole process, so closing the single window
    // (and reopening it from the Dock) restores the same state — and playback
    // keeps going while no window is open. The player also persists its last
    // track so a fresh launch repopulates the now-playing bar.
    @State private var player = PlayerState(store: UserDefaultsPlaybackStore())
    @State private var auth = AuthStore()
    @State private var selection: ContentView.Section = .home

    var body: some Scene {
        // `Window` (not `WindowGroup`) is a single unique window: no "New Window"
        // command and no ⌘N, so the user can't open multiple copies.
        Window("YT Music", id: "main") {
            ContentView(selection: $selection)
                .environment(player)
                .environment(auth)
        }
    }
}
