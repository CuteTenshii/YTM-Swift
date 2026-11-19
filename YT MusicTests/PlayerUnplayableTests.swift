//
//  PlayerUnplayableTests.swift
//  YT MusicTests
//

import Testing
import Foundation
@testable import YT_Music

@Suite("PlayerState unplayable tracks")
@MainActor
struct PlayerStateUnplayableTests {

    private func tracks(_ ids: [String]) -> [Track] {
        ids.enumerated().map { i, id in
            Track(index: i + 1, title: "T\(i)", subtitle: "A", duration: nil,
                  thumbnailURL: nil, videoId: id)
        }
    }

    @Test("An unplayable track in a queue is skipped with a notice")
    func skipsUnplayableTrack() async {
        let audio = FakeAudioOutput()
        let p = PlayerState(audio: audio, resolver: StubResolver(failing: ["a"]))
        p.play(tracks(["a", "b"]), startAt: 0)

        await eventually { audio.loadedURL != nil }

        #expect(p.nowPlaying?.videoId == "b")
        #expect(p.loadError == nil)
        #expect(p.skipNotice?.contains("T0") == true)
    }

    @Test("Auto-skipping stops after too many failures in a row")
    func stopsAfterRepeatedFailures() async {
        let audio = FakeAudioOutput()
        let p = PlayerState(audio: audio, resolver: StubResolver(failing: ["a", "b", "c", "d"]))
        p.play(tracks(["a", "b", "c", "d"]), startAt: 0)

        await eventually { p.loadError != nil }

        #expect(p.currentIndex == PlayerState.maxFailuresInARow - 1)
        #expect(p.loadError != nil)
        #expect(audio.loadedURL == nil)
    }

    @Test("The last unplayable track shows the error instead of skipping")
    func lastTrackShowsError() async {
        let p = PlayerState(audio: FakeAudioOutput(), resolver: StubResolver(failing: ["b"]))
        p.play(tracks(["a", "b"]), startAt: 1)

        await eventually { p.loadError != nil }

        #expect(p.nowPlaying?.videoId == "b")
        #expect(p.skipNotice == nil)
    }

    @Test("A track that plays resets the failure count")
    func successResetsFailures() async {
        let audio = FakeAudioOutput()
        let p = PlayerState(audio: audio, resolver: StubResolver(failing: ["a", "c", "d"]))
        p.play(tracks(["a", "b", "c", "d", "e"]), startAt: 0)
        await eventually { p.nowPlaying?.videoId == "b" && audio.loadedURL != nil }

        audio.onTrackFinished?()
        await eventually { p.nowPlaying?.videoId == "e" || p.loadError != nil }

        #expect(p.nowPlaying?.videoId == "e")
        #expect(p.loadError == nil)
    }

    @Test("Retry reloads the failed track")
    func retryReloads() async {
        let resolver = StubResolver(shouldThrow: true)
        let p = PlayerState(audio: FakeAudioOutput(), resolver: resolver)
        p.play(title: "S", subtitle: "A", thumbnailURL: nil, videoId: "vid")
        await eventually { p.loadError != nil }

        p.retry()

        #expect(p.loadError == nil)
        #expect(p.isLoading)
        await eventually { resolver.calls.calls.count == 2 }
        #expect(resolver.calls.calls.map(\.videoId) == ["vid", "vid"])
    }
}
