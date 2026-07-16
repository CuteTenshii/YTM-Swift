//
//  SongInsightViewModel.swift
//  YT Music
//

import SwiftUI

@MainActor
@Observable
final class SongInsightViewModel {
    enum State {
        case idle
        case loading
        case loaded(SongInsight)
        case unavailable   // no lyrics to work from
        case failed(String)
    }

    private(set) var state: State = .idle

    private let insightProvider: SongInsightProviding
    private let lyricsProvider: LyricsProviding
    /// The track being loaded, so a slow generation for a previous track can't
    /// overwrite the state after the user has moved on.
    private var currentVideoId: String?

    /// Whether the on-device model is available at all — the card hides entirely
    /// when false, so unsupported Macs never see it.
    var isSupported: Bool { insightProvider.isSupported }

    init(insightProvider: SongInsightProviding = SongInsightService(),
         lyricsProvider: LyricsProviding = InnerTubeClient.shared) {
        self.insightProvider = insightProvider
        self.lyricsProvider = lyricsProvider
    }

    /// Fetches the track's lyrics, then generates an on-device insight from them.
    /// No-op when the model is unsupported; `.unavailable` when the track has no
    /// lyrics to interpret.
    func load(query: LyricsQuery?) async {
        guard insightProvider.isSupported, let query else { state = .idle; return }
        currentVideoId = query.videoId
        state = .loading
        do {
            guard let lyrics = try await lyricsProvider.lyrics(for: query),
                  !lyrics.text.isEmpty else {
                guard currentVideoId == query.videoId else { return }
                state = .unavailable
                return
            }
            let insight = try await insightProvider.insight(
                title: query.title, artist: query.artist, lyrics: lyrics.text)
            guard currentVideoId == query.videoId else { return }
            state = .loaded(insight)
        } catch {
            guard currentVideoId == query.videoId else { return }
            state = .failed(error.localizedDescription)
        }
    }
}
