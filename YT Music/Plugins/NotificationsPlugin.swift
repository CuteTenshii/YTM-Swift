//
//  NotificationsPlugin.swift
//  YT Music
//
//

import Foundation

@MainActor
final class NotificationsPlugin: Plugin {
    let id = "track-notifications"
    let name = String(localized: "plugins.notifications.name")
    let summary = String(localized: "plugins.notifications.summary")

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
