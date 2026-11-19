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
        let toasts = ToastCenter()
        let p = PlayerState(audio: audio, resolver: StubResolver(failing: ["a"]), toasts: toasts)
        p.play(tracks(["a", "b"]), startAt: 0)

        await eventually { audio.loadedURL != nil }

        #expect(p.nowPlaying?.videoId == "b")
        #expect(p.loadError == nil)
        #expect(toasts.current?.message.contains("T0") == true)
        #expect(toasts.current?.style == .info)
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

    @Test("The last unplayable track shows an error toast with Retry instead of skipping")
    func lastTrackShowsError() async {
        let toasts = ToastCenter()
        let p = PlayerState(audio: FakeAudioOutput(), resolver: StubResolver(failing: ["b"]), toasts: toasts)
        p.play(tracks(["a", "b"]), startAt: 1)

        await eventually { p.loadError != nil }

        #expect(p.nowPlaying?.videoId == "b")
        #expect(toasts.current?.style == .error)
        #expect(toasts.current?.message == p.loadError)
        #expect(toasts.current?.action != nil)
    }

    @Test("The error toast's Retry reloads the track and clears the toast")
    func toastRetryReloads() async {
        let resolver = StubResolver(shouldThrow: true)
        let toasts = ToastCenter()
        let p = PlayerState(audio: FakeAudioOutput(), resolver: resolver, toasts: toasts)
        p.play(title: "S", subtitle: "A", thumbnailURL: nil, videoId: "vid")
        await eventually { toasts.current != nil }

        toasts.current?.action?.perform()

        #expect(toasts.current == nil)
        #expect(p.isLoading)
        await eventually { resolver.calls.calls.count == 2 }
        #expect(resolver.calls.calls.count == 2)
    }

    @Test("Playing another track dismisses the error toast")
    func newTrackDismissesErrorToast() async {
        let toasts = ToastCenter()
        let p = PlayerState(audio: FakeAudioOutput(), resolver: StubResolver(failing: ["a"]), toasts: toasts)
        p.play(title: "S", subtitle: "A", thumbnailURL: nil, videoId: "a")
        await eventually { toasts.current != nil }

        p.play(title: "S", subtitle: "A", thumbnailURL: nil, videoId: "b")

        #expect(toasts.current == nil)
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
