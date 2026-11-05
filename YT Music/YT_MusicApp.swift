import SwiftUI
import AppKit
import Sparkle
import AppIntents

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        VerticalScrollForwarding.install()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct YT_MusicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var settings: AppSettings
    @State private var player: PlayerState
    @State private var auth = AuthStore()
    @State private var downloader: Downloader
    @State private var pluginHost: PluginHost
    @State private var navigator = Navigator()
    @State private var playlists = PlaylistCoordinator()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    init() {
        CrashHandler.install()

        // Created before the player, which reads audio prefs from it.
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        let player = PlayerState(
            store: UserDefaultsPlaybackStore(),
            settings: settings
        )
        _player = State(initialValue: player)
        AppDependencyManager.shared.add(dependency: player)

        let downloader = Downloader()
        _downloader = State(initialValue: downloader)
        let plugins: [any Plugin] = [
            DiscordPlugin(player: player),
            NotificationsPlugin(),
            LastfmPlugin(),
            DownloaderPlugin(downloader: downloader),
            SponsorBlockPlugin(player: player),
            ReturnYouTubeDislikePlugin(),
        ]
        _pluginHost = State(initialValue: PluginHost(plugins: plugins))
    }

    var body: some Scene {
        // Single Window, not WindowGroup: no New Window command or multiple copies.
        Window("YouTube Music", id: "main") {
            ContentView()
                .environment(player)
                .environment(auth)
                .environment(settings)
                .environment(downloader)
                .environment(pluginHost)
                .environment(navigator)
                .environment(playlists)
                .pluginBridge(player: player, host: pluginHost)
        }
        .commands {
            MediaCommands(player: player, navigator: navigator)
            UpdateCommands(updater: updaterController.updater)
        }

        Window("window.stats.title", id: "stats") {
            StatsForNerdsView(player: player)
        }
        .windowResizability(.contentSize)

        // Scenes don't inherit environments, so inject app state again.
        Settings {
            SettingsView(updater: updaterController.updater)
                .environment(player)
                .environment(auth)
                .environment(settings)
                .environment(downloader)
                .environment(pluginHost)
                .environment(navigator)
                .environment(playlists)
        }
    }
}
