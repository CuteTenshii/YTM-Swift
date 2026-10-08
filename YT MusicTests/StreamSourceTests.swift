//
//  StreamSourceTests.swift
//  YT MusicTests
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Stream source")
struct StreamSourceTests {

    private func tracking(_ params: String) -> Data {
        Data("""
        {"responseContext":{"serviceTrackingParams":[
          {"service":"CSI","params":[{"key":"c","value":"WEB_REMIX"}]},
          {"service":"GFEEDBACK","params":[\(params)]}
        ]}}
        """.utf8)
    }

    @Test("Premium shows as has_unlimited_entitlement=True on a signed-in response")
    func premium() {
        let data = tracking(#"{"key":"has_unlimited_entitlement","value":"True"},{"key":"logged_in","value":"1"}"#)
        #expect(InnerTubeClient.premiumEntitlement(in: data) == true)
    }

    @Test("A signed-in response without the entitlement isn't Premium")
    func notPremium() {
        #expect(InnerTubeClient.premiumEntitlement(in: tracking(#"{"key":"logged_in","value":"1"}"#)) == false)
    }

    @Test("A response that isn't signed in says nothing about Premium")
    func signedOut() {
        #expect(InnerTubeClient.premiumEntitlement(in: tracking(#"{"key":"logged_in","value":"0"}"#)) == nil)
        #expect(InnerTubeClient.premiumEntitlement(in: Data("{}".utf8)) == nil)
    }

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
