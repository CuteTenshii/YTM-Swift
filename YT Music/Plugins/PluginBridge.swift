//
//  PluginBridge.swift
//  YT Music
//
//

import SwiftUI

private struct PluginBridge: ViewModifier {
    let player: PlayerState
    let host: PluginHost

    func body(content: Content) -> some View {
        content.onAppear {
            player.onPlaybackChange = { host.playbackDidChange($0) }
            player.onPlaybackProgress = { host.playbackDidProgress(currentTime: $0, duration: $1) }
            host.playbackDidChange(player.currentSnapshot)
        }
    }
}

extension View {
    func pluginBridge(player: PlayerState, host: PluginHost) -> some View {
        modifier(PluginBridge(player: player, host: host))
    }
}
