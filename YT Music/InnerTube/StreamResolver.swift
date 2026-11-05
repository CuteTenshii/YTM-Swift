//
//  StreamResolver.swift
//  YT Music
//

import Foundation
import OSLog

enum StreamError: LocalizedError {
    case notPlayable(String)
    case noCompatibleAudio

    var errorDescription: String? {
        switch self {
        case .notPlayable(let reason): "Can't play this track: \(reason)"
        case .noCompatibleAudio:       "No AAC audio stream was available for this track."
        }
    }
}

struct ResolvedStream: Sendable {
    let url: URL
    let duration: Double?
    /// Ping to record the play in watch history; nil when omitted.
    var historyURL: URL? = nil
    var watchtimeURL: URL? = nil
    /// Content-playback nonce reused for the history ping so YouTube correlates it with the stream.
    var cpn: String? = nil
    /// Track loudness relative to YouTube's reference level, in dB (positive is louder).
    var loudnessDb: Double? = nil
    var streamEnd: Double? = nil
    var isEpisode = false
    var details: StreamDetails? = nil
}

struct StreamDetails: Sendable, Equatable {
    let videoId: String
    let itag: Int?
    let mimeType: String?
    let bitrate: Int?
    let audioQuality: String?
    let host: String?
    let source: String
}

protocol StreamResolving: Sendable {
    /// `playlistId` attributes the listen to that playlist or radio.
    func audioStream(videoId: String, playlistId: String?, preferences: StreamPreferences) async throws -> ResolvedStream
}

extension StreamResolving {
    func audioStream(videoId: String) async throws -> ResolvedStream {
        try await audioStream(videoId: videoId, playlistId: nil, preferences: StreamPreferences())
    }

    func audioStream(videoId: String, preferences: StreamPreferences) async throws -> ResolvedStream {
        try await audioStream(videoId: videoId, playlistId: nil, preferences: preferences)
    }
}

actor StreamResolver: StreamResolving {
    private static let log = Logger(category: "playback")
    static let shared = StreamResolver()

    private let client = InnerTubeClient.shared
    private let decipher = SignatureDecipher.shared

    func audioStream(videoId: String, playlistId: String?, preferences: StreamPreferences) async throws -> ResolvedStream {
        let signedIn = await CredentialStore.shared.isSignedIn
        let premium = signedIn ? await client.hasPremium() : false
        Self.log.note("resolving videoId=\(videoId) playlist=\(playlistId ?? "-") "
            + "signedIn=\(signedIn) premium=\(premium)")

        // YT Music's own streams stall without a PO token unless Premium, so others use visionOS.
        let response: PlayerResponse
        let streamSource: PlayerResponse
        var sourceName = "WEB_REMIX"
        if !signedIn {
            response = try await playerResponse(videoId: videoId, playlistId: nil, fromMusic: false)
            streamSource = response
            sourceName = "visionOS"
        } else if premium {
            response = try await playerResponse(videoId: videoId, playlistId: playlistId, fromMusic: true)
            streamSource = response
        } else {
            async let vision = try? playerResponse(videoId: videoId, playlistId: nil, fromMusic: false)
            response = try await playerResponse(videoId: videoId, playlistId: playlistId, fromMusic: true)
            if let playable = playableStream(await vision, preferences: preferences) {
                streamSource = playable
                sourceName = "visionOS"
            } else {
                Self.log.note("visionOS can't play this track; streaming from WEB_REMIX")
                streamSource = response
            }
        }

        let status = response.playabilityStatus?.status ?? "nil"
        let adaptiveCount = response.streamingData?.adaptiveFormats?.count ?? 0
        Self.log.note(
            "playabilityStatus=\(status) · adaptiveFormats=\(adaptiveCount) "
                + "· lengthSeconds=\(response.videoDetails?.lengthSeconds ?? "nil")"
        )

        try checkPlayability(response)

        let format = try selectAudioFormat(streamSource, preferences: preferences)
        Self.log.note("selected itag=\(format.itag ?? -1) mime=\(format.mimeType ?? "?") quality=\(preferences.audioQuality.rawValue)")

        // One cpn tags the media fetch and the history ping so the play counts.
        let cpn = WatchHistory.generateCPN()
        let deciphered = try await decipher.streamURL(for: format)
        let url = WatchHistory.appendingCPN(to: deciphered, cpn: cpn)
        Self.log.note("resolved stream host=\(url.host ?? "?")")

        let historyURL = response.playbackTracking?.videostatsPlaybackUrl?.baseUrl
            .flatMap { URL(string: $0) }
        let watchtimeURL = response.playbackTracking?.videostatsWatchtimeUrl?.baseUrl
            .flatMap { URL(string: $0) }
        let duration = format.approxDuration ?? response.videoDetails?.duration
        Self.log.note("duration=\(duration.map { String($0) } ?? "nil")s "
            + "(approxDurationMs=\(format.approxDurationMs ?? "nil"))")
        return ResolvedStream(url: url, duration: duration,
                              historyURL: historyURL, watchtimeURL: watchtimeURL, cpn: cpn,
                              loudnessDb: format.loudnessDb ?? streamSource.playerConfig?.audioConfig?.loudnessDb,
                              streamEnd: format.approxDuration,
                              isEpisode: response.videoDetails?.isEpisode ?? false,
                              details: StreamDetails(videoId: videoId, itag: format.itag, mimeType: format.mimeType,
                                                     bitrate: format.bitrate, audioQuality: format.audioQuality,
                                                     host: url.host, source: sourceName))
    }

    /// A visionOS response isn't valid for the user's own uploads.
    nonisolated func playableStream(_ response: PlayerResponse?, preferences: StreamPreferences) -> PlayerResponse? {
        guard let response, (try? checkPlayability(response)) != nil,
              (try? selectAudioFormat(response, preferences: preferences)) != nil else { return nil }
        return response
    }

    /// Short retry for transient connection resets and server errors only.
    private func playerResponse(videoId: String, playlistId: String?, fromMusic: Bool) async throws -> PlayerResponse {
        let delays: [UInt64] = [0, 300_000_000, 1_000_000_000]
        var lastError: Error?

        for (attempt, delay) in delays.enumerated() {
            if delay > 0 { try await Task.sleep(nanoseconds: delay) }
            do {
                guard fromMusic else { return try await client.signedOutPlayer(videoId: videoId) }
                return try await client.player(
                    videoId: videoId,
                    signatureTimestamp: try await decipher.signatureTimestamp(),
                    playlistId: playlistId
                )
            } catch {
                lastError = error
                guard attempt < delays.count - 1, Self.isTransient(error) else { throw error }
                Self.log.note("transient player request failure; retrying attempt \(attempt + 2)")
            }
        }

        throw lastError ?? InnerTubeError.emptyResponse
    }

    nonisolated static func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }
        switch error {
        case InnerTubeError.emptyResponse:
            return true
        case InnerTubeError.badStatus(let code):
            return (500...599).contains(code)
        default:
            return false
        }
    }

    /// Throws on LOGIN_REQUIRED, UNPLAYABLE, ERROR; a missing status or OK is playable.
    nonisolated func checkPlayability(_ response: PlayerResponse) throws {
        guard let status = response.playabilityStatus?.status, status != "OK" else { return }
        let reason = response.playabilityStatus?.reason ?? status
        Self.log.problem("not playable: \(reason)")
        throw StreamError.notPlayable(reason)
    }

    /// Honours prefer-audio (muxed only as fallback) and audio quality (a rung on the bitrate ladder).
    nonisolated func selectAudioFormat(
        _ response: PlayerResponse,
        preferences: StreamPreferences = StreamPreferences()
    ) throws -> PlayerResponse.Format {
        let adaptiveAudio = (response.streamingData?.adaptiveFormats ?? [])
            .filter { $0.isAudio && $0.isAVPlayerCompatible }
        let muxed = (response.streamingData?.formats ?? [])
            .filter { $0.isAVPlayerCompatible }

        if preferences.preferAudioOverVideo {
            if let chosen = pick(from: adaptiveAudio, quality: preferences.audioQuality) {
                return chosen
            }
            if let chosen = pick(from: muxed, quality: preferences.audioQuality) {
                return chosen
            }
        } else {
            if let chosen = pick(from: adaptiveAudio + muxed, quality: preferences.audioQuality) {
                return chosen
            }
        }
        throw StreamError.noCompatibleAudio
    }

    private nonisolated func pick(
        from formats: [PlayerResponse.Format],
        quality: AudioQuality
    ) -> PlayerResponse.Format? {
        let ranked = formats.sorted { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
        guard !ranked.isEmpty else { return nil }
        switch quality {
        case .low:           return ranked.first
        case .medium:        return ranked[ranked.count / 2]
        case .high, .auto:   return ranked.last
        }
    }
}
