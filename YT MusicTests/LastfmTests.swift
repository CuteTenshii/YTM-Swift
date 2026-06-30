//
//  LastfmTests.swift
//  YT MusicTests
//
//  Tests for the Last.fm scrobbler's pure pieces: the api_sig signature, the
//  scrobble-eligibility rule, and the ScrobbleTracker state machine that turns
//  the discrete PlaybackSnapshot stream into nowPlaying/scrobble actions. The
//  network/auth/Keychain layer (LastfmClient) needs live network and is not
//  covered, matching the rest of the suite.
//

import Testing
import Foundation
@testable import YT_Music

// MARK: - Signature

@Suite("Last.fm signature")
struct LastfmSignatureTests {

    @Test("Signs sorted name+value pairs plus the secret as md5-hex")
    func signsSortedParams() {
        // "a1" + "b2" + "mysecret" → md5 (verified with the `md5` CLI).
        let sig = LastfmSignature.sign(["b": "2", "a": "1"], secret: "mysecret")
        #expect(sig == "e8311fe78014acdac0bd0641099f7c12")
    }

    @Test("Excludes format and callback from the signature")
    func excludesFormatAndCallback() {
        let base = ["api_key": "test", "method": "auth.getSession", "token": "ABC"]
        let withFormat = base.merging(["format": "json", "callback": "cb"]) { a, _ in a }
        #expect(LastfmSignature.sign(base, secret: "mysecret")
                == LastfmSignature.sign(withFormat, secret: "mysecret"))
        // And matches the externally-computed md5 of the canonical string.
        #expect(LastfmSignature.sign(base, secret: "mysecret") == "6d6cf663d3890b563f3e055171b20656")
    }
}

// MARK: - Eligibility

@Suite("Last.fm scrobble eligibility")
struct LastfmEligibilityTests {

    @Test("Tracks 30s or shorter never scrobble")
    func shortTracksNeverScrobble() {
        #expect(!lastfmScrobbleEligible(playedSeconds: 30, duration: 30))
        #expect(!lastfmScrobbleEligible(playedSeconds: 1000, duration: 25))
    }

    @Test("Needs half the duration for tracks under 8 minutes")
    func halfDurationThreshold() {
        // 200s track → threshold 100s.
        #expect(!lastfmScrobbleEligible(playedSeconds: 99, duration: 200))
        #expect(lastfmScrobbleEligible(playedSeconds: 100, duration: 200))
    }

    @Test("Caps the threshold at 4 minutes for long tracks")
    func fourMinuteCap() {
        // 1000s track → half is 500s, but the cap is 240s.
        #expect(!lastfmScrobbleEligible(playedSeconds: 239, duration: 1000))
        #expect(lastfmScrobbleEligible(playedSeconds: 240, duration: 1000))
    }
}

// MARK: - Tracker

@Suite("ScrobbleTracker")
struct ScrobbleTrackerTests {

    private func snapshot(_ videoId: String, playing: Bool = true,
                          duration: Double = 200, title: String = "Song") -> PlaybackSnapshot {
        PlaybackSnapshot(title: title, artist: "Artist", album: "Album",
                         videoId: videoId, thumbnailURL: nil,
                         isPlaying: playing, currentTime: 0, duration: duration)
    }

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ offset: Double) -> Date { t0.addingTimeInterval(offset) }

    @Test("Emits nowPlaying when a track starts playing")
    func nowPlayingOnStart() {
        var tracker = ScrobbleTracker()
        let actions = tracker.update(snapshot("a"), now: t0)
        #expect(actions.count == 1)
        if case .nowPlaying(let track) = actions.first {
            #expect(track.title == "Song")
            #expect(track.startedAt == Int(t0.timeIntervalSince1970))
        } else {
            Issue.record("expected nowPlaying")
        }
    }

    @Test("Scrobbles the previous track on track change once it played enough")
    func scrobblesPreviousOnChange() {
        var tracker = ScrobbleTracker()
        _ = tracker.update(snapshot("a", duration: 200), now: t0)
        // 120s later (> half of 200s) the next track starts.
        let actions = tracker.update(snapshot("b", duration: 200), now: at(120))
        let scrobbles = actions.filter { if case .scrobble = $0 { return true } else { return false } }
        #expect(scrobbles.count == 1)
        if case .scrobble(let track)? = scrobbles.first {
            #expect(track.title == "Song")
            #expect(track.startedAt == Int(t0.timeIntervalSince1970))
        }
        // And the new track gets its nowPlaying.
        #expect(actions.contains { if case .nowPlaying = $0 { return true } else { return false } })
    }

    @Test("Does not scrobble a track that wasn't played long enough")
    func noScrobbleForBriefPlay() {
        var tracker = ScrobbleTracker()
        _ = tracker.update(snapshot("a", duration: 200), now: t0)
        let actions = tracker.update(snapshot("b", duration: 200), now: at(30))
        #expect(!actions.contains { if case .scrobble = $0 { return true } else { return false } })
    }

    @Test("Pausing does not count toward played time")
    func pauseStopsAccumulation() {
        var tracker = ScrobbleTracker()
        _ = tracker.update(snapshot("a", duration: 200), now: t0)
        // Pause after 40s; total threshold is 100s.
        _ = tracker.update(snapshot("a", playing: false, duration: 200), now: at(40))
        // Stay paused a long while, then resume — paused span must not count.
        _ = tracker.update(snapshot("a", playing: true, duration: 200), now: at(400))
        // Only 50 more seconds of real play (40 + 50 = 90s < 100s).
        let actions = tracker.update(snapshot("b", duration: 200), now: at(450))
        #expect(!actions.contains { if case .scrobble = $0 { return true } else { return false } })
    }

    @Test("Scrobbles only once per track")
    func scrobblesOnce() {
        var tracker = ScrobbleTracker()
        _ = tracker.update(snapshot("a", duration: 200), now: t0)
        // Pause past the threshold → eligible mid-track.
        let mid = tracker.update(snapshot("a", playing: false, duration: 200), now: at(150))
        #expect(mid.filter { if case .scrobble = $0 { return true } else { return false } }.count == 1)
        // Resume and then change tracks: must not scrobble "a" again.
        _ = tracker.update(snapshot("a", playing: true, duration: 200), now: at(160))
        let end = tracker.update(nil, now: at(200))
        #expect(!end.contains { if case .scrobble = $0 { return true } else { return false } })
    }

    @Test("Scrobbles the final track when playback stops")
    func scrobblesOnStop() {
        var tracker = ScrobbleTracker()
        _ = tracker.update(snapshot("a", duration: 200), now: t0)
        let actions = tracker.update(nil, now: at(120))
        #expect(actions.filter { if case .scrobble = $0 { return true } else { return false } }.count == 1)
    }
}
