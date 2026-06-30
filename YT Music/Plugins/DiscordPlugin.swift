//
//  DiscordPlugin.swift
//  YT Music
//
//  Mirrors the now-playing track to Discord Rich Presence while enabled.
//

import Foundation

@MainActor
final class DiscordPlugin: Plugin {
    let id = "discord-rpc"
    let name = "Discord Rich Presence"
    let summary = "Show the track you're listening to as your Discord status. Requires the Discord desktop app to be running."

    private let rpc = DiscordRPC()
    private var active = false
    private var lastSnapshot: PlaybackSnapshot?

    func setActive(_ active: Bool) {
        self.active = active
        if active {
            if let lastSnapshot { rpc.update(lastSnapshot) }
        } else {
            rpc.disconnect()
        }
    }

    func playbackDidChange(_ snapshot: PlaybackSnapshot?) {
        lastSnapshot = snapshot
        guard active else { return }
        if let snapshot { rpc.update(snapshot) } else { rpc.clearActivity() }
    }
}
