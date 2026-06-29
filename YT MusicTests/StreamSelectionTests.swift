//
//  StreamSelectionTests.swift
//  YT MusicTests
//
//  Tests for audio-format selection and the Format flags that drive it.
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Stream selection")
struct StreamSelectionTests {

    private func response(from json: String) throws -> PlayerResponse {
        try JSONDecoder().decode(PlayerResponse.self, from: Data(json.utf8))
    }

    @Test("Picks AAC/MP4 over higher-bitrate Opus that AVPlayer can't decode")
    func prefersAVPlayerCompatibleAudio() throws {
        let response = try response(from: """
        { "streamingData": { "adaptiveFormats": [
            { "itag": 251, "mimeType": "audio/webm; codecs=\\"opus\\"", "bitrate": 160000, "url": "https://x/opus" },
            { "itag": 140, "mimeType": "audio/mp4; codecs=\\"mp4a.40.2\\"", "bitrate": 130000, "url": "https://x/aac" }
        ] } }
        """)

        let format = try StreamResolver.shared.selectAudioFormat(response)
        #expect(format.itag == 140)
    }

    @Test("Chooses the highest-bitrate compatible audio stream")
    func picksHighestBitrate() throws {
        let response = try response(from: """
        { "streamingData": { "adaptiveFormats": [
            { "itag": 139, "mimeType": "audio/mp4", "bitrate": 48000 },
            { "itag": 140, "mimeType": "audio/mp4", "bitrate": 130000 }
        ] } }
        """)
        let format = try StreamResolver.shared.selectAudioFormat(response)
        #expect(format.itag == 140)
    }

    @Test("Falls back to a muxed MP4 stream when no adaptive audio is compatible")
    func fallsBackToMuxed() throws {
        let response = try response(from: """
        { "streamingData": {
            "adaptiveFormats": [ { "itag": 251, "mimeType": "audio/webm; codecs=\\"opus\\"", "bitrate": 160000 } ],
            "formats": [ { "itag": 18, "mimeType": "video/mp4; codecs=\\"avc1, mp4a.40.2\\"", "bitrate": 500000 } ]
        } }
        """)
        let format = try StreamResolver.shared.selectAudioFormat(response)
        #expect(format.itag == 18)
    }

    @Test("Throws when no compatible stream exists")
    func throwsWhenNoCompatibleStream() throws {
        let response = try response(from: """
        { "streamingData": { "adaptiveFormats": [
            { "itag": 251, "mimeType": "audio/webm; codecs=\\"opus\\"", "bitrate": 160000 }
        ] } }
        """)
        #expect(throws: StreamError.self) {
            try StreamResolver.shared.selectAudioFormat(response)
        }
    }

    @Test("Format flags classify audio and AVPlayer compatibility")
    func formatFlags() throws {
        let response = try response(from: """
        { "streamingData": { "adaptiveFormats": [
            { "itag": 140, "mimeType": "audio/mp4; codecs=\\"mp4a.40.2\\"", "signatureCipher": "s=1&url=2" },
            { "itag": 251, "mimeType": "audio/webm; codecs=\\"opus\\"" },
            { "itag": 137, "mimeType": "video/mp4; codecs=\\"avc1\\"" }
        ] } }
        """)
        let formats = try #require(response.streamingData?.adaptiveFormats)

        #expect(formats[0].isAudio)
        #expect(formats[0].isAVPlayerCompatible)
        #expect(formats[0].cipherString == "s=1&url=2")

        #expect(formats[1].isAudio)
        #expect(!formats[1].isAVPlayerCompatible)   // opus/webm

        #expect(!formats[2].isAudio)                // video
        #expect(formats[2].isAVPlayerCompatible)    // but mp4 container
    }

    // MARK: - Quality preferences

    private func ladder() throws -> PlayerResponse {
        try response(from: """
        { "streamingData": { "adaptiveFormats": [
            { "itag": 139, "mimeType": "audio/mp4", "bitrate": 48000 },
            { "itag": 140, "mimeType": "audio/mp4", "bitrate": 130000 },
            { "itag": 141, "mimeType": "audio/mp4", "bitrate": 256000 }
        ] } }
        """)
    }

    @Test("Low quality picks the lowest-bitrate compatible audio")
    func lowQualityPicksLowest() throws {
        let format = try StreamResolver.shared.selectAudioFormat(
            ladder(), preferences: .init(audioQuality: .low))
        #expect(format.itag == 139)
    }

    @Test("Medium quality picks a middle rung")
    func mediumQualityPicksMiddle() throws {
        let format = try StreamResolver.shared.selectAudioFormat(
            ladder(), preferences: .init(audioQuality: .medium))
        #expect(format.itag == 140)
    }

    @Test("High and auto pick the best available")
    func highQualityPicksBest() throws {
        for quality in [AudioQuality.high, .auto] {
            let format = try StreamResolver.shared.selectAudioFormat(
                ladder(), preferences: .init(audioQuality: quality))
            #expect(format.itag == 141)
        }
    }

    @Test("Prefer-audio keeps audio-only even when a muxed stream has higher bitrate")
    func preferAudioBeatsMuxed() throws {
        let response = try response(from: """
        { "streamingData": {
            "adaptiveFormats": [ { "itag": 140, "mimeType": "audio/mp4", "bitrate": 130000 } ],
            "formats": [ { "itag": 22, "mimeType": "video/mp4; codecs=\\"avc1, mp4a.40.2\\"", "bitrate": 900000 } ]
        } }
        """)
        let format = try StreamResolver.shared.selectAudioFormat(
            response, preferences: .init(audioQuality: .auto, preferAudioOverVideo: true))
        #expect(format.itag == 140)
    }

    @Test("With prefer-audio off, a higher-bitrate muxed stream can win")
    func muxedCanWinWhenNotPreferringAudio() throws {
        let response = try response(from: """
        { "streamingData": {
            "adaptiveFormats": [ { "itag": 140, "mimeType": "audio/mp4", "bitrate": 130000 } ],
            "formats": [ { "itag": 22, "mimeType": "video/mp4; codecs=\\"avc1, mp4a.40.2\\"", "bitrate": 900000 } ]
        } }
        """)
        let format = try StreamResolver.shared.selectAudioFormat(
            response, preferences: .init(audioQuality: .auto, preferAudioOverVideo: false))
        #expect(format.itag == 22)
    }
}
