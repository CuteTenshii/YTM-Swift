//
//  PlayerResponse.swift
//  YT Music
//

import Foundation

struct PlayerResponse: Decodable, Sendable {
    let playabilityStatus: PlayabilityStatus?
    let streamingData: StreamingData?
    let videoDetails: VideoDetails?
    let playbackTracking: PlaybackTracking?
    let playerConfig: PlayerConfig?

    nonisolated struct PlayerConfig: Decodable, Sendable {
        let audioConfig: AudioConfig?

        nonisolated struct AudioConfig: Decodable, Sendable {
            let loudnessDb: Double?
            let perceptualLoudnessDb: Double?
        }
    }

    struct PlayabilityStatus: Decodable, Sendable {
        let status: String?     // "OK", "LOGIN_REQUIRED", "UNPLAYABLE", "ERROR"
        let reason: String?
    }

    /// Pinging `videostatsPlaybackUrl` registers a play in watch history.
    nonisolated struct PlaybackTracking: Decodable, Sendable {
        let videostatsPlaybackUrl: TrackingURL?
        let videostatsWatchtimeUrl: TrackingURL?

        nonisolated struct TrackingURL: Decodable, Sendable {
            let baseUrl: String?
        }
    }

    /// `lengthSeconds` is the true length; AVPlayer's duration can be off while buffering.
    nonisolated struct VideoDetails: Decodable, Sendable {
        let lengthSeconds: String?
        let title: String?
        let author: String?
        let musicVideoType: String?

        var duration: Double? { lengthSeconds.flatMap(Double.init) }
        var isEpisode: Bool { musicVideoType == "MUSIC_VIDEO_TYPE_PODCAST_EPISODE" }
    }

    struct StreamingData: Decodable, Sendable {
        let adaptiveFormats: [Format]?
        let formats: [Format]?
    }

    /// Either `url` is direct or it is hidden inside `signatureCipher`.
    nonisolated struct Format: Decodable, Sendable {
        let itag: Int?
        let mimeType: String?
        let bitrate: Int?
        let url: String?
        let signatureCipher: String?
        let cipher: String?         // older key name
        let audioQuality: String?
        let loudnessDb: Double?
        /// Milliseconds; `lengthSeconds` is whole seconds.
        let approxDurationMs: String?

        var cipherString: String? { signatureCipher ?? cipher }

        var approxDuration: Double? {
            approxDurationMs.flatMap(Double.init).map { $0 / 1000 }
        }

        var isAudio: Bool { (mimeType ?? "").hasPrefix("audio/") }

        /// AVFoundation can't decode Opus/WebM, so only MP4/AAC is considered.
        var isAVPlayerCompatible: Bool {
            let type = mimeType ?? ""
            return type.contains("mp4") || type.contains("mp4a")
        }
    }
}
