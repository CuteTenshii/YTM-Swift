//
//  WatchHistoryTracker.swift
//  YT Music
//

import Foundation

/// Fires the current track's YT Music history beacons: one playback ping, then periodic watchtime.
final class WatchHistoryTracker {
    private static let watchtimeInterval: Double = 20

    private let reporter: WatchHistoryReporting
    private var pending: ResolvedStream?
    private var playbackPinged = false
    private var lastWatchtimeAt: Double = -1

    init(reporter: WatchHistoryReporting) {
        self.reporter = reporter
    }

    func reset() {
        pending = nil
        playbackPinged = false
        lastWatchtimeAt = -1
    }

    /// Arms on load; beacons fire from `progress` once the listener is underway.
    func arm(_ resolved: ResolvedStream) {
        guard resolved.historyURL != nil || resolved.watchtimeURL != nil, resolved.cpn != nil else { return }
        pending = resolved
        playbackPinged = false
        lastWatchtimeAt = -1
    }

    func progress(current: Double, duration: Double, isPlaying: Bool) {
        guard let pending, let cpn = pending.cpn, isPlaying, current >= 1 else { return }
        let length = pending.duration ?? (duration > 0 ? duration : nil)

        if !playbackPinged, let playbackURL = pending.historyURL {
            playbackPinged = true
            Task { await reporter.reportPlaybackStart(
                playbackURL: playbackURL, cpn: cpn, position: current, length: length) }
        }
        if let watchtimeURL = pending.watchtimeURL,
           lastWatchtimeAt < 0 || current - lastWatchtimeAt >= Self.watchtimeInterval {
            lastWatchtimeAt = current
            Task { await reporter.reportWatchtime(
                watchtimeURL: watchtimeURL, cpn: cpn, position: current, length: length) }
        }
    }

    func finish(engineDuration: Double) {
        guard playbackPinged, let pending, let cpn = pending.cpn,
              let watchtimeURL = pending.watchtimeURL else { return }
        let length = pending.duration
        let position = length ?? engineDuration
        Task { await reporter.reportWatchtime(
            watchtimeURL: watchtimeURL, cpn: cpn, position: position, length: length) }
    }
}
