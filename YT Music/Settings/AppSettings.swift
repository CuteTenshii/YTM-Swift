//
//  AppSettings.swift
//  YT Music
//

import SwiftUI

/// Mapped onto bitrate-ranked adaptive streams, not fixed kbps (YouTube's ladder varies).
nonisolated enum AudioQuality: String, Codable, CaseIterable, Sendable, Identifiable {
    case low
    case medium
    case high
    case auto

    var id: Self { self }

    var label: String {
        switch self {
        case .low:    String(localized: "settings.quality.low")
        case .medium: String(localized: "settings.quality.medium")
        case .high:   String(localized: "settings.quality.high")
        case .auto:   String(localized: "settings.quality.auto")
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case fr

    var id: Self { self }

    var label: String {
        switch self {
        case .system: String(localized: "settings.general.language.system")
        case .en:     "English"
        case .fr:     "Français"
        }
    }
}

nonisolated struct StreamPreferences: Sendable, Equatable {
    var audioQuality: AudioQuality = .auto
    /// Prefer audio-only adaptive streams; muxed is a last resort.
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

    /// Turns down tracks louder than YouTube's reference level.
    var volumeNormalization: Bool {
        didSet {
            store(volumeNormalization, for: .volumeNormalization)
            onVolumeNormalizationChange?(volumeNormalization)
        }
    }

    @ObservationIgnored var onVolumeNormalizationChange: ((Bool) -> Void)?

    var autoplay: Bool {
        didSet { store(autoplay, for: .autoplay) }
    }

    /// Optional HTTP(S) proxy; blank uses the system configuration.
    var proxyURL: String {
        didSet { store(proxyURL.isEmpty ? nil : proxyURL, for: .proxyURL) }
    }

    /// Applies on next launch: macOS reads `AppleLanguages` from the app's defaults at startup.
    var language: AppLanguage {
        didSet {
            if language == .system {
                defaults.removeObject(forKey: Self.appleLanguagesKey)
            } else {
                defaults.set([language.rawValue], forKey: Self.appleLanguagesKey)
            }
        }
    }

    private static let appleLanguagesKey = "AppleLanguages"

    @ObservationIgnored private let launchLanguage: AppLanguage

    var needsRelaunchForLanguage: Bool { language != launchLanguage }

    func relaunch() {
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = ["-c", "sleep 0.5; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        try? relauncher.run()
        NSApp.terminate(nil)
    }

    // MARK: Track lists

    var playOnSingleClick: Bool {
        didSet { store(playOnSingleClick, for: .playOnSingleClick) }
    }

    var playClickCount: Int { playOnSingleClick ? 1 : 2 }

    // MARK: Lyrics

    var lyricsProvider: LyricsProvider {
        didSet { store(lyricsProvider.rawValue, for: .lyricsProvider) }
    }

    var volume: Double {
        didSet { store(volume, for: .volume) }
    }

    var isMuted: Bool {
        didSet { store(isMuted, for: .isMuted) }
    }

    /// Speed for podcast episodes. Music always plays at 1x.
    var podcastPlaybackRate: Double {
        didSet { store(podcastPlaybackRate, for: .podcastPlaybackRate) }
    }

    // MARK: Crossfade

    var crossfadeEnabled: Bool {
        didSet { store(crossfadeEnabled, for: .crossfadeEnabled) }
    }

    var crossfadeSeconds: Double {
        didSet { store(crossfadeSeconds, for: .crossfadeSeconds) }
    }

    /// How early to resolve and buffer the next queued track. Zero disables it.
    var nextTrackPreloadSeconds: Double {
        didSet { store(nextTrackPreloadSeconds, for: .nextTrackPreloadSeconds) }
    }

    // MARK: Equalizer

    var equalizerEnabled: Bool {
        didSet {
            store(equalizerEnabled, for: .equalizerEnabled)
            notifyEqualizerChanged()
        }
    }

    var equalizerGains: [Double] {
        didSet {
            store(try? JSONEncoder().encode(equalizerGains), for: .equalizerGains)
            notifyEqualizerChanged()
        }
    }

    @ObservationIgnored var onEqualizerChange: ((EqualizerSettings) -> Void)?

    var equalizerSettings: EqualizerSettings {
        EqualizerSettings(isEnabled: equalizerEnabled, gains: equalizerGains)
    }

    func applyEqualizerPreset(_ preset: EqualizerPreset) {
        equalizerGains = preset.gains
    }

    private func notifyEqualizerChanged() {
        onEqualizerChange?(equalizerSettings)
    }

    // MARK: Startup

    /// Mirrors the system login item, which the user can also change in System Settings.
    var openAtLogin: Bool {
        didSet { LoginItem.setEnabled(openAtLogin) }
    }

    // MARK: Downloader

    /// Security-scoped bookmark; set via `setDownloadDirectory(_:)`. nil uses Downloads.
    /// Persisted so write access survives relaunches under the sandbox.
    private(set) var downloadDirectory: URL?

    var streamPreferences: StreamPreferences {
        StreamPreferences(audioQuality: audioQuality,
                          preferAudioOverVideo: preferAudioOverVideo)
    }

    var effectiveDownloadDirectory: URL {
        downloadDirectory ?? FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.audioQuality = (defaults.string(forKey: Key.audioQuality.rawValue)
            .flatMap(AudioQuality.init)) ?? .auto
        self.preferAudioOverVideo = defaults.object(forKey: Key.preferAudioOverVideo.rawValue) as? Bool ?? true
        self.volumeNormalization = defaults.bool(forKey: Key.volumeNormalization.rawValue)
        self.autoplay = defaults.object(forKey: Key.autoplay.rawValue) as? Bool ?? true
        self.proxyURL = defaults.string(forKey: Key.proxyURL.rawValue) ?? ""
        let language = (defaults.stringArray(forKey: Self.appleLanguagesKey)?.first)
            .flatMap { AppLanguage(rawValue: String($0.prefix(2))) } ?? .system
        self.language = language
        self.launchLanguage = language
        self.playOnSingleClick = defaults.bool(forKey: Key.playOnSingleClick.rawValue)
        self.lyricsProvider = (defaults.string(forKey: Key.lyricsProvider.rawValue)
            .flatMap(LyricsProvider.init)) ?? .youtubeMusic
        self.volume = defaults.object(forKey: Key.volume.rawValue) as? Double ?? 1
        self.isMuted = defaults.bool(forKey: Key.isMuted.rawValue)
        self.podcastPlaybackRate = defaults.object(forKey: Key.podcastPlaybackRate.rawValue) as? Double ?? 1
        self.crossfadeEnabled = defaults.bool(forKey: Key.crossfadeEnabled.rawValue)
        self.crossfadeSeconds = defaults.object(forKey: Key.crossfadeSeconds.rawValue) as? Double ?? 6
        self.nextTrackPreloadSeconds = defaults.object(forKey: Key.nextTrackPreloadSeconds.rawValue) as? Double ?? 0
        self.equalizerEnabled = defaults.bool(forKey: Key.equalizerEnabled.rawValue)
        self.equalizerGains = Self.decodeGains(defaults.data(forKey: Key.equalizerGains.rawValue))
        self.downloadDirectory = Self.resolveBookmark(defaults.data(forKey: Key.downloadDirectory.rawValue))
        self.openAtLogin = LoginItem.isEnabled
    }

    /// Always returns exactly `EqualizerBands.count` entries.
    private static func decodeGains(_ data: Data?) -> [Double] {
        guard let data,
              let gains = try? JSONDecoder().decode([Double].self, from: data) else {
            return EqualizerSettings.flat.gains
        }
        return EqualizerSettings(isEnabled: false, gains: gains).normalizedGains
    }

    func setDownloadDirectory(_ url: URL?) {
        guard let url else {
            downloadDirectory = nil
            store(nil, for: .downloadDirectory)
            return
        }
        downloadDirectory = url
        let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        store(bookmark, for: .downloadDirectory)
    }

    /// Held open for the app's lifetime.
    private static func resolveBookmark(_ data: Data?) -> URL? {
        guard let data else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    // MARK: - Persistence

    private enum Key: String {
        case audioQuality        = "settings.audioQuality"
        case preferAudioOverVideo = "settings.preferAudioOverVideo"
        case volumeNormalization = "settings.volumeNormalization"
        case autoplay            = "settings.autoplay"
        case proxyURL            = "settings.proxyURL"
        case playOnSingleClick   = "settings.playOnSingleClick"
        case lyricsProvider      = "settings.lyricsProvider"
        case volume              = "settings.volume"
        case isMuted             = "settings.isMuted"
        case podcastPlaybackRate = "settings.podcastPlaybackRate"
        case crossfadeEnabled    = "settings.crossfadeEnabled"
        case crossfadeSeconds    = "settings.crossfadeSeconds"
        case nextTrackPreloadSeconds = "settings.nextTrackPreloadSeconds"
        case equalizerEnabled    = "settings.equalizerEnabled"
        case equalizerGains      = "settings.equalizerGains"
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
