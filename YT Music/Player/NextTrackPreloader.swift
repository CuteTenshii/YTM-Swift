//
//  NextTrackPreloader.swift
//  YT Music
//

import Foundation

/// Resolves the upcoming track's stream ahead of time and hands it over when that track starts.
final class NextTrackPreloader {
    private var videoId: String?
    private var stream: ResolvedStream?
    private var task: Task<Void, Never>?

    var isIdle: Bool { videoId == nil && task == nil }

    /// `accept` runs once resolved and returns false when the stream is no longer wanted.
    func start(videoId: String, resolve: @escaping () async throws -> ResolvedStream,
               accept: @escaping (ResolvedStream) -> Bool) {
        task = Task { [weak self] in
            defer { self?.task = nil }
            guard let resolved = try? await resolve(), !Task.isCancelled, let self else { return }
            guard accept(resolved) else { return }
            self.videoId = videoId
            self.stream = resolved
        }
    }

    func take(_ videoId: String) -> ResolvedStream? {
        guard self.videoId == videoId, let stream else { return nil }
        self.videoId = nil
        self.stream = nil
        return stream
    }

    /// Drops any preload that isn't for `videoId`.
    func discard(keeping videoId: String) {
        guard self.videoId != videoId else { return }
        task?.cancel()
        task = nil
        self.videoId = nil
        stream = nil
    }
}
