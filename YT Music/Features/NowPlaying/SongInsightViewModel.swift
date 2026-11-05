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
        case unavailable
        case failed(String)
    }

    private(set) var state: State = .idle

    private let insightProvider: SongInsightProviding
    private let lyricsProvider: LyricsProviding
    private var currentVideoId: String?

    var isSupported: Bool { insightProvider.isSupported }

    init(insightProvider: SongInsightProviding = SongInsightService(),
         lyricsProvider: LyricsProviding = InnerTubeClient.shared) {
        self.insightProvider = insightProvider
        self.lyricsProvider = lyricsProvider
    }

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
