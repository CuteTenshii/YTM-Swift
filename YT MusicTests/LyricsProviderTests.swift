//
//  LyricsProviderTests.swift
//  YT MusicTests
//
//  Verifies the lyrics view model routes to the selected provider, and the
//  LRCLIB plain-lyrics shaping. Network-free (providers are faked / no live
//  request is made).
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Lyrics provider selection")
@MainActor
struct LyricsProviderTests {

    /// Records which provider was asked, and returns a canned result.
    private final class FakeProvider: LyricsProviding, @unchecked Sendable {
        let lyrics: Lyrics?
        nonisolated(unsafe) private(set) var queried: LyricsQuery?
        init(_ lyrics: Lyrics?) { self.lyrics = lyrics }
        func lyrics(for query: LyricsQuery) async throws -> Lyrics? {
            queried = query
            return lyrics
        }
    }

    private func query() -> LyricsQuery {
        LyricsQuery(videoId: "v1", title: "Song", artist: "Artist", album: "Album", duration: 200)
    }

    @Test("Selecting LRCLIB routes the request to the LRCLIB provider")
    func routesToLrclib() async {
        let yt = FakeProvider(Lyrics(text: "yt", source: nil))
        let lrc = FakeProvider(Lyrics(text: "lrc", source: "Source: LRCLIB"))
        let model = LyricsViewModel(youtubeMusic: yt, lrclib: lrc)

        await model.load(query: query(), provider: .lrclib)

        #expect(lrc.queried?.videoId == "v1")
        #expect(yt.queried == nil)
        guard case .loaded(let lyrics) = model.state else { return #expect(Bool(false)) }
        #expect(lyrics.text == "lrc")
    }

    @Test("Selecting YouTube Music routes to the YT provider")
    func routesToYouTubeMusic() async {
        let yt = FakeProvider(Lyrics(text: "yt", source: nil))
        let lrc = FakeProvider(nil)
        let model = LyricsViewModel(youtubeMusic: yt, lrclib: lrc)

        await model.load(query: query(), provider: .youtubeMusic)

        #expect(yt.queried?.title == "Song")
        #expect(lrc.queried == nil)
    }

    @Test("A provider with no match yields the unavailable state")
    func unavailableWhenNoMatch() async {
        let model = LyricsViewModel(youtubeMusic: FakeProvider(nil), lrclib: FakeProvider(nil))
        await model.load(query: query(), provider: .youtubeMusic)
        guard case .unavailable = model.state else { return #expect(Bool(false)) }
    }

    @Test("A nil query (nothing playing) is unavailable without hitting a provider")
    func unavailableWhenNoTrack() async {
        let yt = FakeProvider(Lyrics(text: "yt", source: nil))
        let model = LyricsViewModel(youtubeMusic: yt, lrclib: FakeProvider(nil))
        await model.load(query: nil, provider: .youtubeMusic)
        guard case .unavailable = model.state else { return #expect(Bool(false)) }
        #expect(yt.queried == nil)
    }
}
