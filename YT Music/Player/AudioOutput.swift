//
//  AudioOutput.swift
//  YT Music
//
//  Abstraction over the audio engine so PlayerState can be tested with a fake.
//

import Foundation

/// Metadata shown in the system Now Playing UI (Control Center, media keys).
struct NowPlayingMetadata: Sendable, Equatable {
    var title: String
    var artist: String
    var album: String
    var artworkURL: URL?
    /// Preferred over AVPlayer's `duration`, which can over-estimate while buffering.
    var knownDuration: Double? = nil
    /// Track loudness in dB relative to YouTube's reference, for volume normalization.
    var loudnessDb: Double? = nil
    /// Precise stream length where playback is cut off; nil leaves the end to AVPlayer.
    var streamEnd: Double? = nil
    var isEpisode = false
}

@MainActor
protocol AudioOutput: AnyObject {
    var isPlaying: Bool { get }
    /// Audio is genuinely flowing (not paused, not buffering).
    var isActuallyPlaying: Bool { get }
    var isBuffering: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    /// Seconds buffered ahead; drives the scrubber cache fill.
    var bufferedTime: Double { get }
    /// 0...1, applied as master gain on top of any crossfade.
    var volume: Double { get set }
    var normalizesVolume: Bool { get set }
    var playbackRate: Double { get set }

    var onTrackFinished: (() -> Void)? { get set }
    /// Fires when audio actually starts (buffering to playing), not at load.
    var onPlaybackStart: (() -> Void)? { get set }
    var onTogglePlayPause: (() -> Void)? { get set }
    var onNext: (() -> Void)? { get set }
    var onPrevious: (() -> Void)? { get set }
    var onProgress: ((Double, Double) -> Void)? { get set }

    func load(url: URL, metadata: NowPlayingMetadata)
    func preload(url: URL, metadata: NowPlayingMetadata)
    func loadPreloaded(url: URL, metadata: NowPlayingMetadata)
    func togglePlayPause()
    func seek(to seconds: Double)
    /// Restarts the current item without re-resolving the URL.
    func restart()
    func crossfade(to url: URL, metadata: NowPlayingMetadata, duration: Double)
    func crossfadePreloaded(url: URL, metadata: NowPlayingMetadata, duration: Double)
    func applyEqualizer(_ settings: EqualizerSettings)

    /// nil for outputs without a meter (e.g. the test fake).
    var spectrum: SpectrumAnalyzer? { get }
}

extension AudioOutput {
    func preload(url: URL, metadata: NowPlayingMetadata) {}
    func loadPreloaded(url: URL, metadata: NowPlayingMetadata) { load(url: url, metadata: metadata) }
    func crossfadePreloaded(url: URL, metadata: NowPlayingMetadata, duration: Double) {
        crossfade(to: url, metadata: metadata, duration: duration)
    }
    func applyEqualizer(_ settings: EqualizerSettings) {}
    var spectrum: SpectrumAnalyzer? { nil }
    var normalizesVolume: Bool { get { false } set {} }
    var playbackRate: Double { get { 1 } set {} }
    var isActuallyPlaying: Bool { isPlaying }
    var isBuffering: Bool { false }
    var onPlaybackStart: (() -> Void)? { get { nil } set {} }
    var onTogglePlayPause: (() -> Void)? { get { nil } set {} }
}
