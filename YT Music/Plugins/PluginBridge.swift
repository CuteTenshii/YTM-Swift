//
//  PluginBridge.swift
//  YT Music
//
//  Single connection between playback and the plugin system: forwards every
//  PlayerState change to the PluginHost, which fans it out to enabled plugins.
//  Adding or removing plugins never touches this file.
//

import SwiftUI

private struct PluginBridge: ViewModifier {
    let player: PlayerState
    let host: PluginHost

    func body(content: Content) -> some View {
        content.onAppear {
            player.onPlaybackChange = { host.playbackDidChange($0) }
            host.playbackDidChange(player.currentSnapshot)
        }
    }
}

extension View {
    /// Routes playback changes into the plugin host.
    func pluginBridge(player: PlayerState, host: PluginHost) -> some View {
        modifier(PluginBridge(player: player, host: host))
    }
}
