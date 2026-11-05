//
//  PlaybackIntents.swift
//  YT Music
//
//  App Intents for Shortcuts, Siri and Spotlight.
//

import AppIntents

struct NothingPlayingError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource { "intent.error.nothing_playing" }
}

struct TogglePlayPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.play_pause.title"
    static let description = IntentDescription("intent.play_pause.description")

    @Dependency private var player: PlayerState

    @MainActor
    func perform() async throws -> some IntentResult {
        guard player.nowPlaying != nil else { throw NothingPlayingError() }
        player.togglePlayPause()
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.next.title"
    static let description = IntentDescription("intent.next.description")

    @Dependency private var player: PlayerState

    @MainActor
    func perform() async throws -> some IntentResult {
        guard player.nowPlaying != nil else { throw NothingPlayingError() }
        player.next()
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.previous.title"
    static let description = IntentDescription("intent.previous.description")

    @Dependency private var player: PlayerState

    @MainActor
    func perform() async throws -> some IntentResult {
        guard player.nowPlaying != nil else { throw NothingPlayingError() }
        player.previous()
        return .result()
    }
}

struct LikeCurrentTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.like.title"
    static let description = IntentDescription("intent.like.description")

    @Dependency private var player: PlayerState

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let videoId = player.nowPlaying?.videoId else { throw NothingPlayingError() }
        player.setLikeStatus(for: videoId, to: .liked)
        return .result()
    }
}

struct StartRadioIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.radio.title"
    static let description = IntentDescription("intent.radio.description")

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
            shortTitle: "intent.play_pause.title",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: NextTrackIntent(),
            phrases: ["Next track in \(.applicationName)", "Skip song in \(.applicationName)"],
            shortTitle: "intent.next.title",
            systemImageName: "forward.fill"
        )
        AppShortcut(
            intent: PreviousTrackIntent(),
            phrases: ["Previous track in \(.applicationName)"],
            shortTitle: "intent.previous.title",
            systemImageName: "backward.fill"
        )
        AppShortcut(
            intent: LikeCurrentTrackIntent(),
            phrases: ["Like this song in \(.applicationName)", "Like the current track in \(.applicationName)"],
            shortTitle: "intent.like.short",
            systemImageName: "hand.thumbsup.fill"
        )
        AppShortcut(
            intent: StartRadioIntent(),
            phrases: ["Start radio in \(.applicationName)", "Start a radio from this song in \(.applicationName)"],
            shortTitle: "intent.radio.short",
            systemImageName: "dot.radiowaves.left.and.right"
        )
    }
}
