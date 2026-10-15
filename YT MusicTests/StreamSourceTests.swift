//
//  StreamSourceTests.swift
//  YT MusicTests
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Stream source")
struct StreamSourceTests {

    private func response(_ json: String) throws -> PlayerResponse {
        try JSONDecoder().decode(PlayerResponse.self, from: Data(json.utf8))
    }

    @Test("A playable response with AAC audio can be streamed from")
    func playable() throws {
        let vision = try response("""
        {"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[
          {"itag":140,"mimeType":"audio/mp4; codecs=\\"mp4a.40.2\\"","bitrate":130000,"url":"https://x/aac"}]}}
        """)
        #expect(StreamResolver.shared.playableStream(vision, preferences: StreamPreferences()) != nil)
    }

    @Test("Unplayable, audio-less, or missing responses fall back")
    func fallsBack() throws {
        let unplayable = try response(#"{"playabilityStatus":{"status":"LOGIN_REQUIRED"}}"#)
        let noAudio = try response(#"{"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[]}}"#)
        #expect(StreamResolver.shared.playableStream(unplayable, preferences: StreamPreferences()) == nil)
        #expect(StreamResolver.shared.playableStream(noAudio, preferences: StreamPreferences()) == nil)
        #expect(StreamResolver.shared.playableStream(nil, preferences: StreamPreferences()) == nil)
    }
}
