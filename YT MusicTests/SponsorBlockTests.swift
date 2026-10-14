//
//  SponsorBlockTests.swift
//  YT MusicTests
//

import Testing
import Foundation
@testable import YT_Music

@Suite("SponsorBlock")
struct SponsorBlockTests {

    @Test("Builds the skipSegments URL with sorted JSON categories and skip-only actions")
    func buildsURL() throws {
        let url = try #require(SponsorBlockAPI.segmentsURL(videoId: "abc123", categories: [.sponsor, .musicOfftopic]))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host == "sponsor.ajay.app")
        #expect(url.path == "/api/skipSegments")
        #expect(query["videoID"] == "abc123")
        #expect(query["categories"] == #"["music_offtopic","sponsor"]"#)
        #expect(query["actionTypes"] == #"["skip"]"#)
    }

    @Test("Decodes skip segments and drops unknown categories, other actions, and bad ranges")
    func decodes() throws {
        let json = """
        [
          {"UUID": "a", "segment": [0, 12.5], "category": "music_offtopic", "actionType": "skip", "videoDuration": 240},
          {"UUID": "b", "segment": [30, 40], "category": "exclusive_access", "actionType": "full"},
          {"UUID": "c", "segment": [50, 60], "category": "sponsor", "actionType": "mute"},
          {"UUID": "d", "segment": [70, 65], "category": "intro", "actionType": "skip"},
          {"UUID": "e", "segment": [200, 240], "category": "outro"}
        ]
        """
        let segments = try SponsorBlockAPI.decode(Data(json.utf8))
        #expect(segments == [
            SponsorSegment(id: "a", start: 0, end: 12.5, category: .musicOfftopic),
            SponsorSegment(id: "e", start: 200, end: 240, category: .outro),
        ])
    }

    @Test("Picks the segment under the playhead unless already skipped")
    func picksSegment() {
        let segments = [
            SponsorSegment(id: "a", start: 0, end: 10, category: .intro),
            SponsorSegment(id: "b", start: 100, end: 120, category: .outro),
        ]
        #expect(SponsorBlockAPI.segmentToSkip(at: 0, in: segments, skipped: [])?.id == "a")
        #expect(SponsorBlockAPI.segmentToSkip(at: 10, in: segments, skipped: []) == nil)
        #expect(SponsorBlockAPI.segmentToSkip(at: 50, in: segments, skipped: []) == nil)
        #expect(SponsorBlockAPI.segmentToSkip(at: 110, in: segments, skipped: [])?.id == "b")
        #expect(SponsorBlockAPI.segmentToSkip(at: 110, in: segments, skipped: ["b"]) == nil)
    }
}
