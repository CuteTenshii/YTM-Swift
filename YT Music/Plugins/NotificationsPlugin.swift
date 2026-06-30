//
//  NotificationsPlugin.swift
//  YT Music
//
//  Posts a system notification on each track change while enabled.
//

import Foundation

@MainActor
final class NotificationsPlugin: Plugin {
    let id = "track-notifications"
    let name = "Track notifications"
    let summary = "Show a system notification with the title and artist whenever the playing track changes."

    private let notifier = TrackChangeNotifier()
    private var active = false

    func setActive(_ active: Bool) {
        self.active = active
        if active { notifier.requestAuthorization() }
    }

    func playbackDidChange(_ snapshot: PlaybackSnapshot?) {
        notifier.handle(snapshot, enabled: active)
    }
}
