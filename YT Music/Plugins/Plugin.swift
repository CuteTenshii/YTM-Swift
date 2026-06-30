//
//  Plugin.swift
//  YT Music
//
//  A plugin is a self-contained, toggleable feature that reacts to playback
//  and/or exposes its own settings UI. Adding one means writing a single type
//  and registering it in the array passed to `PluginHost` (see YT_MusicApp) —
//  nothing in AppSettings, the Settings screen, or the playback bridge needs to
//  change.
//

import SwiftUI

@MainActor
protocol Plugin: AnyObject, Identifiable {
    /// Stable identifier used to persist the enabled state. Don't change it once
    /// shipped, or users will silently lose their toggle.
    var id: String { get }
    var name: String { get }
    /// One-line description shown under the toggle.
    var summary: String { get }

    /// Called when the user enables/disables the plugin, and once at launch for
    /// plugins that were enabled in a previous session.
    func setActive(_ active: Bool)
    /// Called on every track / play-pause change (nil = playback stopped).
    func playbackDidChange(_ snapshot: PlaybackSnapshot?)
    /// Optional configuration UI, shown under the toggle while enabled.
    var configuration: AnyView? { get }
}

extension Plugin {
    func setActive(_ active: Bool) {}
    func playbackDidChange(_ snapshot: PlaybackSnapshot?) {}
    var configuration: AnyView? { nil }
}
