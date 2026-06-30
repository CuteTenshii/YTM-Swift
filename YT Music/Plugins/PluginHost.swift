//
//  PluginHost.swift
//  YT Music
//
//  Owns the registered plugins, persists which are enabled, and fans playback
//  changes out to the enabled ones. The single integration point for plugins:
//  the app builds the array, the Settings screen renders it, and PluginBridge
//  feeds it playback updates.
//

import SwiftUI

@MainActor
@Observable
final class PluginHost {
    let plugins: [any Plugin]

    private var enabledIDs: Set<String>
    private let defaults: UserDefaults
    private let storageKey = "plugins.enabled"

    init(plugins: [any Plugin], defaults: UserDefaults = .standard) {
        self.plugins = plugins
        self.defaults = defaults
        self.enabledIDs = Set(defaults.stringArray(forKey: storageKey) ?? [])
        // Bring previously-enabled plugins online.
        for plugin in plugins where enabledIDs.contains(plugin.id) {
            plugin.setActive(true)
        }
    }

    func isEnabled(_ plugin: any Plugin) -> Bool { enabledIDs.contains(plugin.id) }

    func setEnabled(_ enabled: Bool, for plugin: any Plugin) {
        if enabled { enabledIDs.insert(plugin.id) } else { enabledIDs.remove(plugin.id) }
        defaults.set(Array(enabledIDs), forKey: storageKey)
        plugin.setActive(enabled)
    }

    func playbackDidChange(_ snapshot: PlaybackSnapshot?) {
        for plugin in plugins where enabledIDs.contains(plugin.id) {
            plugin.playbackDidChange(snapshot)
        }
    }
}
