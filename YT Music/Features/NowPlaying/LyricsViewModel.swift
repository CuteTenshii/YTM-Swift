//
//  LyricsViewModel.swift
//  YT Music
//

import SwiftUI

@MainActor
@Observable
final class LyricsViewModel {
    enum State {
        case idle
        case loading
        case loaded(Lyrics)
        case unavailable
        case failed(String)
    }

    private(set) var state: State = .idle

    private let youtubeMusic: LyricsProviding
    private let lrclib: LyricsProviding
    private let musixmatch: LyricsProviding

    init(youtubeMusic: LyricsProviding = InnerTubeClient.shared,
         lrclib: LyricsProviding = LRCLibClient.shared,
         musixmatch: LyricsProviding = MusixmatchClient.shared) {
        self.youtubeMusic = youtubeMusic
        self.lrclib = lrclib
        self.musixmatch = musixmatch
    }

    func load(query: LyricsQuery?, provider: LyricsProvider) async {
        guard let query else { state = .unavailable; return }
        state = .loading
        let client: LyricsProviding = switch provider {
        case .youtubeMusic: youtubeMusic
        case .lrclib:       lrclib
        case .musixmatch:   musixmatch
        }
        do {
            if let lyrics = try await client.lyrics(for: query) {
                state = .loaded(lyrics)
            } else {
                state = .unavailable
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
