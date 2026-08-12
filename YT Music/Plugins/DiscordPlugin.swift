//
//  DiscordPlugin.swift
//  YT Music
//
//  Mirrors the now-playing track to Discord Rich Presence while enabled. The
//  configuration UI lets the user pick how the track is laid out across the
//  presence's two text lines (song/artist, artist/song, …).
//

import SwiftUI

@MainActor
@Observable
final class DiscordPlugin: Plugin {
    let id = "discord-rpc"
    let name = "Discord Rich Presence"
    let summary = "Show the track you're listening to as your Discord status. Requires the Discord desktop app to be running."

    private let rpc = DiscordRPC()
    private let defaults: UserDefaults
    private var active = false
    /// The player to read live state from (e.g. the current track position when
    /// re-pushing after a config change). Weak so the plugin never retains it.
    private weak var player: PlayerState?

    /// Which field feeds the "Listening to …" status text in the member list.
    var statusDisplay: DiscordStatusDisplay {
        didSet {
            defaults.set(statusDisplay.rawValue, forKey: Self.displayKey)
            repush()
        }
    }

    /// When enabled, video titles in "Artist - Track" form are split and the
    /// artist/track taken from the title — the byline's artist on such uploads
    /// is often just the uploader channel, not the real artist.
    var parseTitleAsArtistTrack: Bool {
        didSet {
            defaults.set(parseTitleAsArtistTrack, forKey: Self.parseTitleKey)
            repush()
        }
    }

    init(player: PlayerState? = nil, defaults: UserDefaults = .standard) {
        self.player = player
        self.defaults = defaults
        self.statusDisplay = defaults.string(forKey: Self.displayKey)
            .flatMap(DiscordStatusDisplay.init) ?? .name
        self.parseTitleAsArtistTrack = defaults.object(forKey: Self.parseTitleKey) as? Bool ?? false
    }

    private static let displayKey = "plugins.discord-rpc.display"
    private static let parseTitleKey = "plugins.discord-rpc.parse-title"

    /// Re-sends the current track's presence after a config change, reading the
    /// live snapshot from the player so the progress bar keeps its real position.
    private func repush() {
        guard active, let snapshot = player?.currentSnapshot else { return }
        rpc.update(snapshot, style: statusDisplay, parseTitle: parseTitleAsArtistTrack)
    }

    func setActive(_ active: Bool) {
        self.active = active
        if active {
            repush()
        } else {
            rpc.disconnect()
        }
    }

    func playbackDidChange(_ snapshot: PlaybackSnapshot?) {
        guard active else { return }
        if let snapshot {
            rpc.update(snapshot, style: statusDisplay, parseTitle: parseTitleAsArtistTrack)
        } else {
            rpc.clearActivity()
        }
    }

    var configuration: AnyView? { AnyView(DiscordConfigView(plugin: self)) }
}

/// Status text picker shown under the toggle.
private struct DiscordConfigView: View {
    @Bindable var plugin: DiscordPlugin

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status display type")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Status display type", selection: $plugin.statusDisplay) {
                ForEach(DiscordStatusDisplay.allCases) { display in
                    Text(display.label).tag(display)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Text("Controls what appears after “Listening to …” on your profile.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Parse video titles as “Artist — Track”", isOn: $plugin.parseTitleAsArtistTrack)
            Text("For uploads whose byline only names the uploader channel, take the artist from the video title instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
