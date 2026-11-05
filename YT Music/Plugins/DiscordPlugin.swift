//
//  DiscordPlugin.swift
//  YT Music
//
//

import SwiftUI

@MainActor
@Observable
final class DiscordPlugin: Plugin {
    let id = "discord-rpc"
    let name = "Discord Rich Presence"
    let summary = String(localized: "plugins.discord.summary")

    private let rpc = DiscordRPC()
    private let defaults: UserDefaults
    private var active = false
    private weak var player: PlayerState?

    var statusDisplay: DiscordStatusDisplay {
        didSet {
            defaults.set(statusDisplay.rawValue, forKey: Self.displayKey)
            repush()
        }
    }

    /// Splits "Artist - Track" video titles; the byline artist is often the uploader.
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

private struct DiscordConfigView: View {
    @Bindable var plugin: DiscordPlugin

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("plugins.discord.display")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("plugins.discord.display", selection: $plugin.statusDisplay) {
                ForEach(DiscordStatusDisplay.allCases) { display in
                    Text(display.label).tag(display)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Text("plugins.discord.display.help")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("plugins.discord.parse_title", isOn: $plugin.parseTitleAsArtistTrack)
            Text("plugins.discord.parse_title.help")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
