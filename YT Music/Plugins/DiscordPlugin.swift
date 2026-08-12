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
    private var lastSnapshot: PlaybackSnapshot?

    /// Which field feeds the "Listening to …" status text in the member list.
    var statusDisplay: DiscordStatusDisplay {
        didSet {
            defaults.set(statusDisplay.rawValue, forKey: Self.storageKey)
            guard active, let lastSnapshot else { return }
            rpc.update(lastSnapshot, style: statusDisplay)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.statusDisplay = defaults.string(forKey: Self.storageKey)
            .flatMap(DiscordStatusDisplay.init) ?? .name
    }

    private static let storageKey = "plugins.discord-rpc.display"

    func setActive(_ active: Bool) {
        self.active = active
        if active {
            if let lastSnapshot { rpc.update(lastSnapshot, style: statusDisplay) }
        } else {
            rpc.disconnect()
        }
    }

    func playbackDidChange(_ snapshot: PlaybackSnapshot?) {
        lastSnapshot = snapshot
        guard active else { return }
        if let snapshot { rpc.update(snapshot, style: statusDisplay) } else { rpc.clearActivity() }
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
        }
    }
}
