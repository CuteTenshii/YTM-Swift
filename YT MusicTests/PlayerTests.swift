//
//  PlayerTests.swift
//  YT MusicTests
//
//  Tests for the playback layer. PlayerState's resolve→load/error orchestration
//  is driven through injected fakes (no network, no audio hardware); AudioPlayer's
//  no-item transport guards are tested on the real instance.
//

import Testing
import Foundation
@testable import YT_Music

// MARK: - Test doubles

enum StubError: Error { case boom }

nonisolated struct StubResolver: StreamResolving {
    var url = URL(string: "https://stream.example.com/audio.m4a")!
    var duration: Double? = nil
    var shouldThrow = false

    func audioStream(videoId: String, preferences: StreamPreferences) async throws -> ResolvedStream {
        if shouldThrow { throw StubError.boom }
        return ResolvedStream(url: url, duration: duration)
    }
}

nonisolated struct StubRadio: RadioProviding {
    var tracks: [Track] = []
    func radio(for videoId: String) async throws -> [Track] { tracks }
}

@MainActor
final class InMemoryStore: PlaybackStore {
    var snapshot: PersistedPlayback?
    func load() -> PersistedPlayback? { snapshot }
    func save(_ snapshot: PersistedPlayback?) { self.snapshot = snapshot }
}

@MainActor
final class FakeAudioOutput: AudioOutput {
    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0
    var onTrackFinished: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    private(set) var loadedURL: URL?
    private(set) var loadedMetadata: NowPlayingMetadata?
    private(set) var toggleCount = 0
    private(set) var seekedTo: Double?
    private(set) var restartCount = 0

    func load(url: URL, metadata: NowPlayingMetadata) {
        loadedURL = url
        loadedMetadata = metadata
        isPlaying = true
    }
    func togglePlayPause() { toggleCount += 1; isPlaying.toggle() }
    func seek(to seconds: Double) { seekedTo = seconds; currentTime = seconds }
    func restart() { restartCount += 1; currentTime = 0; isPlaying = true }
}

// MARK: - PlayerState

@Suite("PlayerState")
@MainActor
struct PlayerStateTests {

    private func track(videoId: String?) -> Track {
        Track(index: 1, title: "Song", subtitle: "Artist", duration: nil,
              thumbnailURL: nil, videoId: videoId)
    }

    @Test("play() records now-playing and enters loading")
    func playSetsState() {
        let player = PlayerState(audio: FakeAudioOutput(), resolver: StubResolver())
        player.play(title: "Song", subtitle: "Artist", thumbnailURL: nil, videoId: "vid")
        #expect(player.nowPlaying?.videoId == "vid")
        #expect(player.isLoading)
    }

    @Test("play(track:) without a video id is a no-op")
    func ignoresTrackWithoutVideoId() {
        let player = PlayerState(audio: FakeAudioOutput(), resolver: StubResolver())
        player.play(track(videoId: nil))
        #expect(player.nowPlaying == nil)
        #expect(!player.isLoading)
    }

    @Test("Successful resolve loads the stream and clears loading")
    func loadsStreamOnSuccess() async {
        let audio = FakeAudioOutput()
        let url = URL(string: "https://stream.example.com/track.m4a")!
        let player = PlayerState(audio: audio, resolver: StubResolver(url: url))

        await player.loadStream(videoId: "vid")

        #expect(audio.loadedURL == url)
        #expect(player.loadError == nil)
        #expect(!player.isLoading)
    }

    @Test("Now-playing metadata carries title, artist, and album")
    func metadataIncludesAlbum() async {
        let audio = FakeAudioOutput()
        let player = PlayerState(audio: audio, resolver: StubResolver())
        player.play(title: "Song", subtitle: "Artist", album: "Greatest Hits",
                    thumbnailURL: nil, videoId: "vid")

        await player.loadStream(videoId: "vid")

        #expect(audio.loadedMetadata?.title == "Song")
        #expect(audio.loadedMetadata?.artist == "Artist")
        #expect(audio.loadedMetadata?.album == "Greatest Hits")
    }

    @Test("Uses the authoritative track length from the resolver")
    func usesKnownDuration() async {
        let audio = FakeAudioOutput()
        let player = PlayerState(audio: audio, resolver: StubResolver(duration: 200))
        player.play(title: "S", subtitle: "A", thumbnailURL: nil, videoId: "v")

        await player.loadStream(videoId: "v")

        #expect(audio.loadedMetadata?.knownDuration == 200)
    }

    @Test("Failed resolve surfaces an error and loads nothing")
    func setsErrorOnFailure() async {
        let audio = FakeAudioOutput()
        let player = PlayerState(audio: audio, resolver: StubResolver(shouldThrow: true))
        player.play(title: "S", subtitle: "A", thumbnailURL: nil, videoId: "vid")

        await player.loadStream(videoId: "vid")

        #expect(audio.loadedURL == nil)
        #expect(player.loadError != nil)
        #expect(!player.isLoading)
    }

    @Test("Transport controls proxy to the audio engine")
    func transportProxies() {
        let audio = FakeAudioOutput()
        let player = PlayerState(audio: audio, resolver: StubResolver())

        player.togglePlayPause()
        #expect(audio.toggleCount == 1)

        player.seek(to: 42)
        #expect(audio.seekedTo == 42)
    }
}

// MARK: - Queue, transport & repeat

@Suite("PlayerState queue")
@MainActor
struct PlayerStateQueueTests {

    private func tracks(_ ids: [String?]) -> [Track] {
        ids.enumerated().map { i, id in
            Track(index: i + 1, title: "T\(i)", subtitle: "A", duration: nil,
                  thumbnailURL: nil, videoId: id)
        }
    }

    private func player() -> PlayerState {
        PlayerState(audio: FakeAudioOutput(), resolver: StubResolver())
    }

    @Test("play(queue:) starts at the requested index and records the queue")
    func playsQueueAtIndex() {
        let p = player()
        p.play(tracks(["a", "b", "c"]), startAt: 1)
        #expect(p.queue.count == 3)
        #expect(p.currentIndex == 1)
        #expect(p.nowPlaying?.videoId == "b")
    }

    @Test("play(queue:) filters unplayable tracks and remaps the start")
    func filtersUnplayable() {
        let p = player()
        // Request the (unplayable) middle track → first playable at/after it.
        p.play(tracks(["a", nil, "c"]), startAt: 1)
        #expect(p.queue.map(\.videoId) == ["a", "c"])
        #expect(p.nowPlaying?.videoId == "c")
        #expect(p.currentIndex == 1)
    }

    @Test("next advances and stops at the end when repeat is off")
    func nextStopsAtEnd() {
        let p = player()
        p.play(tracks(["a", "b"]), startAt: 0)
        p.next()
        #expect(p.currentIndex == 1)
        #expect(p.nowPlaying?.videoId == "b")
        p.next() // at end, repeat off → no change
        #expect(p.currentIndex == 1)
        #expect(p.nowPlaying?.videoId == "b")
    }

    @Test("next wraps to the start when repeat is all")
    func nextWrapsWhenRepeatAll() {
        let p = player()
        p.play(tracks(["a", "b"]), startAt: 1)
        p.cycleRepeatMode() // .all
        #expect(p.repeatMode == .all)
        p.next()
        #expect(p.currentIndex == 0)
        #expect(p.nowPlaying?.videoId == "a")
    }

    @Test("previous restarts the current track when more than 3s in")
    func previousRestartsLateInTrack() {
        let audio = FakeAudioOutput()
        let p = PlayerState(audio: audio, resolver: StubResolver())
        p.play(tracks(["a", "b", "c"]), startAt: 2)
        audio.currentTime = 10
        p.previous()
        #expect(audio.seekedTo == 0)
        #expect(p.currentIndex == 2)
    }

    @Test("previous steps back early in a track")
    func previousStepsBackEarly() {
        let audio = FakeAudioOutput()
        let p = PlayerState(audio: audio, resolver: StubResolver())
        p.play(tracks(["a", "b", "c"]), startAt: 2)
        audio.currentTime = 1
        p.previous()
        #expect(p.currentIndex == 1)
        #expect(p.nowPlaying?.videoId == "b")
    }

    @Test("cycleRepeatMode cycles off → all → one → off")
    func cyclesRepeatMode() {
        let p = player()
        #expect(p.repeatMode == .off)
        p.cycleRepeatMode(); #expect(p.repeatMode == .all)
        p.cycleRepeatMode(); #expect(p.repeatMode == .one)
        p.cycleRepeatMode(); #expect(p.repeatMode == .off)
    }

    @Test("a finished track advances to the next when repeat is off")
    func finishAdvances() {
        let audio = FakeAudioOutput()
        let p = PlayerState(audio: audio, resolver: StubResolver())
        p.play(tracks(["a", "b"]), startAt: 0)
        audio.onTrackFinished?()
        #expect(p.currentIndex == 1)
        #expect(p.nowPlaying?.videoId == "b")
    }

    @Test("a finished track replays itself when repeat is one")
    func finishReplaysWhenRepeatOne() {
        let audio = FakeAudioOutput()
        let p = PlayerState(audio: audio, resolver: StubResolver())
        p.play(tracks(["a", "b"]), startAt: 0)
        p.cycleRepeatMode(); p.cycleRepeatMode() // .one
        audio.onTrackFinished?()
        #expect(audio.restartCount == 1)
        #expect(p.currentIndex == 0)
    }

    @Test("canGoNext/canGoPrevious reflect position and repeat mode")
    func navigationAvailability() {
        let p = player()
        p.play(tracks(["a", "b", "c"]), startAt: 0)
        #expect(p.canGoNext)
        #expect(!p.canGoPrevious)
        p.cycleRepeatMode() // .all → wrapping enables previous
        #expect(p.canGoPrevious)
    }

    @Test("a one-off play clears the queue and disables navigation")
    func singlePlayClearsQueue() {
        let p = player()
        p.play(tracks(["a", "b"]), startAt: 0)
        p.play(title: "S", subtitle: "A", thumbnailURL: nil, videoId: "x")
        #expect(p.queue.isEmpty)
        #expect(!p.canGoNext)
        #expect(!p.canGoPrevious)
    }

    @Test("startRadio plays the seed immediately")
    func startRadioPlaysSeed() {
        let radio = StubRadio(tracks: tracks(["seed", "n2"]))
        let p = PlayerState(audio: FakeAudioOutput(), resolver: StubResolver(), radioProvider: radio)
        p.startRadio(title: "Seed", subtitle: "A", thumbnailURL: nil, videoId: "seed")
        #expect(p.nowPlaying?.videoId == "seed")
    }

    @Test("installRadio installs the fetched queue, anchored on the seed")
    func installRadioBuildsQueue() async {
        // Seed first, then more tracks (mirrors the real radio response).
        let radioTracks = [
            Track(index: 1, title: "Seed", subtitle: "A", duration: nil, thumbnailURL: nil, videoId: "seed"),
            Track(index: 2, title: "Next", subtitle: "B", duration: nil, thumbnailURL: nil, videoId: "n2"),
        ]
        let p = PlayerState(audio: FakeAudioOutput(), resolver: StubResolver(),
                            radioProvider: StubRadio(tracks: radioTracks))
        p.play(title: "Seed", subtitle: "A", thumbnailURL: nil, videoId: "seed")

        await p.installRadio(seed: "seed")

        #expect(p.queue.map(\.videoId) == ["seed", "n2"])
        #expect(p.currentIndex == 0)
        #expect(p.canGoNext)
    }

    @Test("installRadio is ignored if the seed is no longer playing")
    func installRadioIgnoredAfterChange() async {
        let p = PlayerState(audio: FakeAudioOutput(), resolver: StubResolver(),
                            radioProvider: StubRadio(tracks: tracks(["seed", "n2"])))
        p.play(title: "Other", subtitle: "A", thumbnailURL: nil, videoId: "other")
        await p.installRadio(seed: "seed")   // seed isn't what's playing
        #expect(p.queue.isEmpty)
    }
}

// MARK: - Persistence / restore

@Suite("PlayerState persistence")
@MainActor
struct PlayerStatePersistenceTests {

    private func snapshot(
        videoId: String,
        tracks: [PersistedPlayback.StoredTrack] = [],
        index: Int = 0,
        repeatMode: PlayerState.RepeatMode = .off
    ) -> PersistedPlayback {
        PersistedPlayback(
            nowPlaying: .init(title: "T", subtitle: "S", album: "A", thumbnailURL: nil, videoId: videoId),
            tracks: tracks, currentIndex: index, repeatMode: repeatMode, album: "A"
        )
    }

    @Test("restores the last track on launch without auto-playing")
    func restoresWithoutPlaying() {
        let store = InMemoryStore()
        store.snapshot = snapshot(videoId: "v")
        let p = PlayerState(audio: FakeAudioOutput(), resolver: StubResolver(), store: store)
        #expect(p.nowPlaying?.videoId == "v")
        #expect(!p.isPlaying)
        #expect(!p.isLoading)
    }

    @Test("playing persists a snapshot")
    func playPersists() {
        let store = InMemoryStore()
        let p = PlayerState(audio: FakeAudioOutput(), resolver: StubResolver(), store: store)
        p.play(title: "Song", subtitle: "Artist", thumbnailURL: nil, videoId: "v")
        #expect(store.snapshot?.nowPlaying.videoId == "v")
    }

    @Test("resuming a restored track starts loading it")
    func resumeStartsLoad() {
        let store = InMemoryStore()
        store.snapshot = snapshot(videoId: "v")
        let p = PlayerState(audio: FakeAudioOutput(), resolver: StubResolver(), store: store)
        #expect(!p.isLoading)
        p.togglePlayPause()   // first play resolves the restored track
        #expect(p.isLoading)
    }

    @Test("restores the queue and repeat mode")
    func restoresQueueAndRepeat() {
        let store = InMemoryStore()
        store.snapshot = snapshot(
            videoId: "a",
            tracks: [
                .init(index: 1, title: "A", subtitle: "x", duration: nil, thumbnailURL: nil, videoId: "a"),
                .init(index: 2, title: "B", subtitle: "y", duration: nil, thumbnailURL: nil, videoId: "b"),
            ],
            index: 0, repeatMode: .all
        )
        let p = PlayerState(audio: FakeAudioOutput(), resolver: StubResolver(), store: store)
        #expect(p.queue.map(\.videoId) == ["a", "b"])
        #expect(p.repeatMode == .all)
        #expect(p.canGoNext)
    }
}

// MARK: - AudioPlayer (real instance, no playback required)

@Suite("AudioPlayer")
@MainActor
struct AudioPlayerTests {

    @Test("seek updates currentTime even with no loaded item")
    func seekUpdatesTime() {
        let player = AudioPlayer()
        player.seek(to: 30)
        #expect(player.currentTime == 30)
    }

    @Test("togglePlayPause is a no-op with nothing loaded")
    func toggleNoOpWhenEmpty() {
        let player = AudioPlayer()
        player.togglePlayPause()
        #expect(player.isPlaying == false)
    }
}
