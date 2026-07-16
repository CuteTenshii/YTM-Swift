//
//  SongInsightViewModelTests.swift
//  YT MusicTests
//
//  Drives the "About this song" view model with fakes, verifying its state
//  transitions without the on-device model or the network.
//

import Testing
import Foundation
@testable import YT_Music

@MainActor
@Suite("Song insight view model")
struct SongInsightViewModelTests {

    private struct FakeInsight: SongInsightProviding {
        var supported = true
        /// The insight to return; nil makes generation throw.
        var result: SongInsight? = SongInsight(summary: "About it.", mood: "Wistful", themes: ["loss"])
        var isSupported: Bool { supported }
        func insight(title: String, artist: String, lyrics: String) async throws -> SongInsight {
            guard let result else { throw SongInsightError.unsupported }
            return result
        }
    }

    private struct FakeLyrics: LyricsProviding {
        var stored: Lyrics?
        func lyrics(for query: LyricsQuery) async throws -> Lyrics? { stored }
    }

    private func query() -> LyricsQuery {
        LyricsQuery(videoId: "v1", title: "Song", artist: "Artist", album: "", duration: nil)
    }

    @Test("Unsupported model → stays idle (card hidden) and reports unsupported")
    func unsupported() async {
        let model = SongInsightViewModel(
            insightProvider: FakeInsight(supported: false),
            lyricsProvider: FakeLyrics(stored: Lyrics(text: "words")))
        #expect(model.isSupported == false)
        await model.load(query: query())
        guard case .idle = model.state else { return #expect(Bool(false)) }
    }

    @Test("Lyrics present → generates and loads an insight")
    func loadsInsight() async {
        let model = SongInsightViewModel(
            insightProvider: FakeInsight(),
            lyricsProvider: FakeLyrics(stored: Lyrics(text: "some lyrics")))
        await model.load(query: query())
        guard case .loaded(let insight) = model.state else { return #expect(Bool(false)) }
        #expect(insight.summary == "About it.")
        #expect(insight.themes == ["loss"])
    }

    @Test("No lyrics → unavailable (nothing to interpret)")
    func noLyrics() async {
        let model = SongInsightViewModel(
            insightProvider: FakeInsight(),
            lyricsProvider: FakeLyrics(stored: nil))
        await model.load(query: query())
        guard case .unavailable = model.state else { return #expect(Bool(false)) }

        // Blank lyric text is treated the same as none.
        let blank = SongInsightViewModel(
            insightProvider: FakeInsight(),
            lyricsProvider: FakeLyrics(stored: Lyrics(text: "")))
        await blank.load(query: query())
        guard case .unavailable = blank.state else { return #expect(Bool(false)) }
    }

    @Test("Generation failure → failed state")
    func generationFails() async {
        let model = SongInsightViewModel(
            insightProvider: FakeInsight(result: nil),
            lyricsProvider: FakeLyrics(stored: Lyrics(text: "lyrics")))
        await model.load(query: query())
        guard case .failed = model.state else { return #expect(Bool(false)) }
    }

    @Test("Nil query (nothing playing) → idle")
    func nilQuery() async {
        let model = SongInsightViewModel(
            insightProvider: FakeInsight(),
            lyricsProvider: FakeLyrics(stored: Lyrics(text: "lyrics")))
        await model.load(query: nil)
        guard case .idle = model.state else { return #expect(Bool(false)) }
    }
}
