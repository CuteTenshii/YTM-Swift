//
//  TrackChangeNotifier.swift
//  YT Music
//
//

import Foundation
import UserNotifications

@MainActor
final class TrackChangeNotifier {
    private var lastVideoId: String?
    private var didRequestAuthorization = false
    /// The first snapshot is restored state, not a change; prime the baseline without notifying.
    private var hasBaseline = false

    func requestAuthorization() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// `lastVideoId` is tracked even while disabled so enabling mid-track doesn't notify.
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
        content.body = parts.joined(separator: " - ")

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
