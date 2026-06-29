//
//  PlayerResponse.swift
//  YT Music
//
//  Decodable models for the InnerTube `player` endpoint, which returns playback
//  status and the available media streams for a video.
//

import Foundation

struct PlayerResponse: Decodable, Sendable {
    let playabilityStatus: PlayabilityStatus?
    let streamingData: StreamingData?
    let videoDetails: VideoDetails?

    struct PlayabilityStatus: Decodable, Sendable {
        let status: String?     // "OK", "LOGIN_REQUIRED", "UNPLAYABLE", "ERROR"
        let reason: String?
    }

    /// Authoritative metadata for the video — notably `lengthSeconds`, which is
    /// the true track length (AVPlayer's `duration` can be a bad estimate while a
    /// progressive stream is still buffering).
    struct VideoDetails: Decodable, Sendable {
        let lengthSeconds: String?
        let title: String?
        let author: String?

        var duration: Double? { lengthSeconds.flatMap(Double.init) }
    }

    struct StreamingData: Decodable, Sendable {
        let expiresInSeconds: String?
        let adaptiveFormats: [Format]?
        let formats: [Format]?
    }

    /// A single media stream. Either `url` is present directly, or the URL is
    /// hidden inside `signatureCipher` and must be deciphered.
    nonisolated struct Format: Decodable, Sendable {
        let itag: Int?
        let mimeType: String?
        let bitrate: Int?
        let url: String?
        let signatureCipher: String?
        let cipher: String?         // older key name
        let audioQuality: String?
        let contentLength: String?

        var cipherString: String? { signatureCipher ?? cipher }

        var isAudio: Bool { (mimeType ?? "").hasPrefix("audio/") }

        /// AVFoundation can't decode Opus/WebM, so we only consider MP4/AAC.
        var isAVPlayerCompatible: Bool {
            let type = mimeType ?? ""
            return type.contains("mp4") || type.contains("mp4a")
        }
    }
}
