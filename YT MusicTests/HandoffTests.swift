//
//  HandoffTests.swift
//  YT MusicTests
//

import Testing
import Foundation
@testable import YT_Music

@MainActor
@Suite("Handoff")
struct HandoffTests {
    private func snapshot(videoId: String) -> PlaybackSnapshot {
        PlaybackSnapshot(title: "Song", artist: "Artist", album: "", videoId: videoId,
                         thumbnailURL: nil, isPlaying: true, currentTime: 0, duration: 200)
    }

    @Test("Advertises the playing track's watch URL")
    func advertisesTrack() {
        let handoff = Handoff()
        handoff.update(snapshot(videoId: "abc123"))
        #expect(handoff.activity?.webpageURL?.absoluteString == "https://music.youtube.com/watch?v=abc123")
        #expect(handoff.activity?.title == "Song - Artist")
        #expect(handoff.activity?.activityType == Handoff.activityType)
    }

    @Test("Follows track changes")
    func followsTrackChanges() {
        let handoff = Handoff()
        handoff.update(snapshot(videoId: "first"))
        handoff.update(snapshot(videoId: "second"))
        #expect(handoff.activity?.webpageURL?.absoluteString == "https://music.youtube.com/watch?v=second")
    }

    @Test("Stops advertising when playback stops")
    func stops() {
        let handoff = Handoff()
        handoff.update(snapshot(videoId: "abc123"))
        handoff.update(nil)
        #expect(handoff.activity == nil)
    }
}
