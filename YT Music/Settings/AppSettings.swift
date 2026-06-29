//
//  AppSettings.swift
//  YT Music
//
//  App-wide user preferences, backed by UserDefaults. Lives for the whole
//  process (env-injected like PlayerState/AuthStore). Each stored property
//  reads its initial value from UserDefaults and writes back on change, so the
//  settings survive relaunches without an explicit save step.
//

import SwiftUI

/// Preferred audio fidelity. The resolver maps this onto the available adaptive
/// streams (which are ranked by bitrate) rather than fixed kbps values, since
/// YouTube's ladder varies per track.
enum AudioQuality: String, Codable, CaseIterable, Sendable, Identifiable {
    case low
    case medium
    case high
    case auto   // always the best available

    var id: Self { self }

    var label: String {
        switch self {
        case .low:    "Low"
        case .medium: "Medium"
        case .high:   "High"
        case .auto:   "Auto (best)"
        }
    }
}

/// The subset of settings the (nonisolated) stream resolver needs. A plain
/// Sendable value so it can be passed across the actor boundary on each resolve.
struct StreamPreferences: Sendable, Equatable {
    var audioQuality: AudioQuality = .auto
    /// When true, music videos are played as audio-only adaptive streams and a
    /// muxed (video+audio) stream is used only as a last resort.
    var preferAudioOverVideo: Bool = true
}

@MainActor
@Observable
final class AppSettings {
    // MARK: Audio

    var audioQuality: AudioQuality {
        didSet { store(audioQuality.rawValue, for: .audioQuality) }
    }

    var preferAudioOverVideo: Bool {
        didSet { store(preferAudioOverVideo, for: .preferAudioOverVideo) }
    }

    // MARK: Crossfade

    var crossfadeEnabled: Bool {
        didSet { store(crossfadeEnabled, for: .crossfadeEnabled) }
    }

    /// Overlap duration, in seconds, between consecutive tracks.
    var crossfadeSeconds: Double {
        didSet { store(crossfadeSeconds, for: .crossfadeSeconds) }
    }

    // MARK: Plugins

    var discordRPCEnabled: Bool {
        didSet { store(discordRPCEnabled, for: .discordRPCEnabled) }
    }

    var downloaderEnabled: Bool {
        didSet { store(downloaderEnabled, for: .downloaderEnabled) }
    }

    /// Where the downloader writes files. nil → the user's Downloads folder.
    var downloadDirectory: URL? {
        didSet { store(downloadDirectory?.path, for: .downloadDirectory) }
    }

    /// Snapshot consumed by the resolver on each track load.
    var streamPreferences: StreamPreferences {
        StreamPreferences(audioQuality: audioQuality,
                          preferAudioOverVideo: preferAudioOverVideo)
    }

    /// Effective download destination, falling back to ~/Downloads.
    var effectiveDownloadDirectory: URL {
        downloadDirectory ?? FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Read persisted values, falling back to sensible defaults.
        self.audioQuality = (defaults.string(forKey: Key.audioQuality.rawValue)
            .flatMap(AudioQuality.init)) ?? .auto
        self.preferAudioOverVideo = defaults.object(forKey: Key.preferAudioOverVideo.rawValue) as? Bool ?? true
        self.crossfadeEnabled = defaults.bool(forKey: Key.crossfadeEnabled.rawValue)
        self.crossfadeSeconds = defaults.object(forKey: Key.crossfadeSeconds.rawValue) as? Double ?? 6
        self.discordRPCEnabled = defaults.bool(forKey: Key.discordRPCEnabled.rawValue)
        self.downloaderEnabled = defaults.bool(forKey: Key.downloaderEnabled.rawValue)
        self.downloadDirectory = defaults.string(forKey: Key.downloadDirectory.rawValue)
            .map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Persistence

    private enum Key: String {
        case audioQuality        = "settings.audioQuality"
        case preferAudioOverVideo = "settings.preferAudioOverVideo"
        case crossfadeEnabled    = "settings.crossfadeEnabled"
        case crossfadeSeconds    = "settings.crossfadeSeconds"
        case discordRPCEnabled   = "settings.discordRPCEnabled"
        case downloaderEnabled   = "settings.downloaderEnabled"
        case downloadDirectory   = "settings.downloadDirectory"
    }

    private func store(_ value: Any?, for key: Key) {
        if let value {
            defaults.set(value, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}
