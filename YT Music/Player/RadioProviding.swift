//
//  RadioProviding.swift
//  YT Music
//

import Foundation

/// A batch of a mix/radio plus a token for its next batch (nil when exhausted).
struct RadioPage: Sendable {
    let tracks: [Track]
    let continuation: String?
}

protocol RadioProviding: Sendable {
    func radio(for videoId: String) async throws -> RadioPage
    func continueRadio(_ token: String) async throws -> RadioPage
    func watchQueue(videoId: String, playlistId: String) async throws -> [Track]
}

extension RadioProviding {
    func watchQueue(videoId: String, playlistId: String) async throws -> [Track] {
        try await radio(for: videoId).tracks
    }
}

extension InnerTubeClient: RadioProviding {}

enum MixIds {
    /// A song's auto-generated radio: `RDAMVM<videoId>`.
    static func songRadio(for videoId: String) -> String { "RDAMVM\(videoId)" }
    /// A playlist's or album's radio: `RDAMPL<playlistId>`.
    static func playlistRadio(for playlistId: String) -> String { "RDAMPL\(playlistId)" }
}
