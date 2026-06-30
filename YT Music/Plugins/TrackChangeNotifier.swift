//
//  TrackChangeNotifier.swift
//  YT Music
//
//  Posts a system notification when the playing track changes. Fed the same
//  PlaybackSnapshot stream as the other plugins (via PluginBridge); fires only
//  when the videoId actually changes, not on play/pause.
//

import Foundation
import UserNotifications

@MainActor
final class TrackChangeNotifier {
    private var lastVideoId: String?
    private var didRequestAuthorization = false
    /// The first snapshot is the state at the moment we start observing — the
    /// track restored from the last session (or nothing), delivered when the
    /// plugin bridge appears. That isn't a track *change*, so we prime the
    /// baseline from it without notifying, to avoid firing on app launch.
    private var hasBaseline = false

    /// Asks for notification permission once (call when the setting is enabled).
    func requestAuthorization() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Posts a notification if `snapshot` is a different track than the last one.
    /// `lastVideoId` is tracked even while disabled, so enabling mid-track doesn't
    /// immediately fire for the song already playing.
    func handle(_ snapshot: PlaybackSnapshot?, enabled: Bool) {
        guard hasBaseline else {
            hasBaseline = true
            lastVideoId = snapshot?.videoId
            return
        }
        guard let snapshot else { lastVideoId = nil; return }
        guard snapshot.videoId != lastVideoId else { return }
        lastVideoId = snapshot.videoId
        guard enabled else { return }
        post(snapshot)
    }

    private func post(_ snapshot: PlaybackSnapshot) {
        let content = UNMutableNotificationContent()
        content.title = snapshot.title.isEmpty ? "Now Playing" : snapshot.title
        let parts = [snapshot.artist, snapshot.album].filter { !$0.isEmpty }
        content.body = parts.joined(separator: " — ")

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil   // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
}
