//
//  ReturnYouTubeDislikePlugin.swift
//  YT Music
//
//  Shows like and dislike counts from Return YouTube Dislike beside the
//  now-playing bar's rating buttons.
//

import Foundation

@MainActor
@Observable
final class ReturnYouTubeDislikePlugin: Plugin {
    let id = "return-youtube-dislike"
    let name = "Return YouTube Dislike"
    let summary = "Show like and dislike counts for the playing track, using the Return YouTube Dislike database."

    /// Counts for `videoId`; nil while loading or when the API has none.
    private(set) var votes: VoteCounts?
    private(set) var videoId: String?

    private let client = ReturnYouTubeDislikeClient()
    private var active = false
    private var fetchTask: Task<Void, Never>?

    func setActive(_ active: Bool) {
        self.active = active
        if !active { reset() }
    }

    func playbackDidChange(_ snapshot: PlaybackSnapshot?) {
        guard active else { return }
        guard let snapshot else {
            reset()
            return
        }
        guard snapshot.videoId != videoId else { return }
        reset()
        videoId = snapshot.videoId
        let videoId = snapshot.videoId
        fetchTask = Task {
            let found = try? await client.votes(videoId: videoId)
            guard !Task.isCancelled, self.videoId == videoId else { return }
            votes = found
        }
    }

    private func reset() {
        fetchTask?.cancel()
        fetchTask = nil
        videoId = nil
        votes = nil
    }
}
