//
//  WatchNextParserTests.swift
//  YT MusicTests
//
//  Verifies the `next`-endpoint decode + parse used by "Start radio", against a
//  fixture shaped like the real response (no network).
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Watch-next (radio) parser")
struct WatchNextParserTests {

    private let fixture = """
    {"contents":{"singleColumnMusicWatchNextResultsRenderer":{"tabbedRenderer":
    {"watchNextTabbedResultsRenderer":{"tabs":[{"tabRenderer":{"content":
    {"musicQueueRenderer":{"content":{"playlistPanelRenderer":{"contents":[
    {"playlistPanelVideoRenderer":{"videoId":"seed","title":{"runs":[{"text":"Seed Song"}]},
    "longBylineText":{"runs":[{"text":"Artist A"}]},"lengthText":{"runs":[{"text":"3:01"}]},
    "thumbnail":{"thumbnails":[{"url":"https://x/1.jpg","width":60,"height":60},
    {"url":"https://x/2.jpg","width":120,"height":120}]}}},
    {"playlistPanelVideoRenderer":{"videoId":"n2","title":{"runs":[{"text":"Next Song"}]},
    "longBylineText":{"runs":[{"text":"Artist B"}]},"lengthText":{"runs":[{"text":"2:45"}]}}},
    {"automixPreviewVideoRenderer":{"content":{}}}
    ]}}}}}}]}}}}}
    """

    @Test("Extracts playable tracks, best thumbnail, and skips non-video rows")
    func parsesQueue() throws {
        let response = try JSONDecoder().decode(WatchNextResponse.self, from: Data(fixture.utf8))
        let tracks = WatchNextParser.parse(response)

        #expect(tracks.count == 2)   // the automix row has no videoId → skipped
        #expect(tracks[0].videoId == "seed")
        #expect(tracks[0].title == "Seed Song")
        #expect(tracks[0].subtitle == "Artist A")
        #expect(tracks[0].duration == "3:01")
        #expect(tracks[0].thumbnailURL?.absoluteString == "https://x/2.jpg")  // highest width
        #expect(tracks[1].videoId == "n2")
        #expect(tracks[1].subtitle == "Artist B")
    }

    @Test("An unrecognized response yields no tracks")
    func emptyOnGarbage() throws {
        let response = try JSONDecoder().decode(WatchNextResponse.self, from: Data("{}".utf8))
        #expect(WatchNextParser.parse(response).isEmpty)
    }

    // Like state lives in the player overlay, scoped to a target videoId.
    private let likeFixture = """
    {"playerOverlays":{"playerOverlayRenderer":{"actions":[
    {"likeButtonRenderer":{"likeStatus":"LIKE","target":{"videoId":"vid"}}}
    ]}}}
    """

    @Test("Reads the seed track's like status from the player overlay")
    func parsesLikeStatus() throws {
        let response = try JSONDecoder().decode(WatchNextResponse.self, from: Data(likeFixture.utf8))
        #expect(WatchNextParser.likeStatus(response, expecting: "vid") == .liked)
    }

    @Test("Like status defaults to indifferent when absent or for a different video")
    func likeStatusDefaults() throws {
        let response = try JSONDecoder().decode(WatchNextResponse.self, from: Data(likeFixture.utf8))
        // Mismatched videoId → don't mislabel this track.
        #expect(WatchNextParser.likeStatus(response, expecting: "other") == .indifferent)

        let empty = try JSONDecoder().decode(WatchNextResponse.self, from: Data("{}".utf8))
        #expect(WatchNextParser.likeStatus(empty, expecting: "vid") == .indifferent)
    }
}
