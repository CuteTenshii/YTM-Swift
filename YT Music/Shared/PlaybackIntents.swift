//
//  PlaybackIntents.swift
//  YT Music
//
//  App Intents for Shortcuts, Siri, and Spotlight. They drive the shared
//  PlayerState registered with AppDependencyManager in YT_MusicApp.
//

import AppIntents

struct NothingPlayingError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource { "Nothing is playing." }
}

struct TogglePlayPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Toggles playback of the current track.")

    @Dependency private var player: PlayerState

    @MainActor
    func perform() async throws -> some IntentResult {
        guard player.nowPlaying != nil else { throw NothingPlayingError() }
        player.togglePlayPause()
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let description = IntentDescription("Skips to the next track in the queue.")

    @Dependency private var player: PlayerState

    @MainActor
    func perform() async throws -> some IntentResult {
        guard player.nowPlaying != nil else { throw NothingPlayingError() }
        player.next()
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous Track"
    static let description = IntentDescription("Restarts the current track, or goes back to the previous one.")

    @Dependency private var player: PlayerState

    @MainActor
    func perform() async throws -> some IntentResult {
        guard player.nowPlaying != nil else { throw NothingPlayingError() }
        player.previous()
        return .result()
    }
}

struct LikeCurrentTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Like Current Track"
    static let description = IntentDescription("Adds the playing track to your liked songs.")

    @Dependency private var player: PlayerState

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let videoId = player.nowPlaying?.videoId else { throw NothingPlayingError() }
        player.setLikeStatus(for: videoId, to: .liked)
        return .result()
    }
}

struct StartRadioIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Radio from Current Track"
    static let description = IntentDescription("Replaces the queue with a radio based on the playing track.")

    @Dependency private var player: PlayerState

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let track = player.nowPlaying else { throw NothingPlayingError() }
        player.startRadio(title: track.title, subtitle: track.subtitle, thumbnailURL: track.thumbnailURL,
                          videoId: track.videoId, artists: track.artists, albumLink: track.albumLink)
        return .result()
    }
}

struct PlaybackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TogglePlayPauseIntent(),
            phrases: ["Play or pause \(.applicationName)", "Toggle \(.applicationName) playback"],
            shortTitle: "Play or Pause",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: NextTrackIntent(),
            phrases: ["Next track in \(.applicationName)", "Skip song in \(.applicationName)"],
            shortTitle: "Next Track",
            systemImageName: "forward.fill"
        )
        AppShortcut(
            intent: PreviousTrackIntent(),
            phrases: ["Previous track in \(.applicationName)"],
            shortTitle: "Previous Track",
            systemImageName: "backward.fill"
        )
        AppShortcut(
            intent: LikeCurrentTrackIntent(),
            phrases: ["Like this song in \(.applicationName)", "Like the current track in \(.applicationName)"],
            shortTitle: "Like Track",
            systemImageName: "hand.thumbsup.fill"
        )
        AppShortcut(
            intent: StartRadioIntent(),
            phrases: ["Start radio in \(.applicationName)", "Start a radio from this song in \(.applicationName)"],
            shortTitle: "Start Radio",
            systemImageName: "dot.radiowaves.left.and.right"
        )
    }
}
