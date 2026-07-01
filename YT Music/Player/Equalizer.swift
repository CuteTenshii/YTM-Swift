//
//  Equalizer.swift
//  YT Music
//
//  A multi-band graphic equalizer applied to playback. This file holds the
//  pure, off-main pieces: the band layout, presets, the persisted settings
//  value, the biquad DSP, and the processor that runs on the audio thread.
//
//  The realtime glue that wires this into AVPlayer (an MTAudioProcessingTap)
//  lives in EqualizerTap.swift; the UI lives in SettingsView. Everything here
//  is `nonisolated` so it can run off the main actor (the tap callback fires on
//  a realtime audio thread) and be exercised directly in tests.
//

import Foundation

/// The fixed band layout: ten ISO octave-spaced center frequencies, the classic
/// graphic-EQ ladder. The count drives the length of every gain array.
nonisolated enum EqualizerBands {
    /// Center frequencies in Hz.
    static let frequencies: [Double] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

    /// Per-band quality factor. ~1.4 gives roughly one-octave bandwidth, so
    /// adjacent bands overlap smoothly rather than leaving notches.
    static let q: Double = 1.41

    /// Gain limits, in dB, for any single band (and the slider range in the UI).
    static let gainRange: ClosedRange<Double> = -12...12

    static var count: Int { frequencies.count }

    /// A short label for a band's frequency (e.g. "500", "2k", "16k").
    static func label(forIndex index: Int) -> String {
        let hz = frequencies[index]
        if hz >= 1_000 {
            let k = hz / 1_000
            return k == k.rounded() ? "\(Int(k))k" : String(format: "%.1fk", k)
        }
        return "\(Int(hz))"
    }
}

/// A named gain curve the user can pick as a starting point. The `gains` arrays
/// are all `EqualizerBands.count` long and stay within `gainRange`.
nonisolated enum EqualizerPreset: String, CaseIterable, Identifiable, Sendable {
    case flat
    case bassBoost
    case trebleBoost
    case vocal
    case rock
    case electronic
    case loudness

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flat:        "Flat"
        case .bassBoost:   "Bass Boost"
        case .trebleBoost: "Treble Boost"
        case .vocal:       "Vocal"
        case .rock:        "Rock"
        case .electronic:  "Electronic"
        case .loudness:    "Loudness"
        }
    }

    //                 32   64  125  250  500   1k   2k   4k   8k  16k
    var gains: [Double] {
        switch self {
        case .flat:        [ 0,   0,   0,   0,   0,   0,   0,   0,   0,   0]
        case .bassBoost:   [ 6,   5,   4,   2,   0,   0,   0,   0,   0,   0]
        case .trebleBoost: [ 0,   0,   0,   0,   0,   1,   2,   4,   5,   6]
        case .vocal:       [-2,  -1,   0,   2,   4,   4,   3,   1,   0,  -1]
        case .rock:        [ 4,   3,   1,  -1,  -1,   0,   2,   3,   4,   4]
        case .electronic:  [ 4,   3,   0,  -1,  -2,   1,   0,   2,   4,   5]
        case .loudness:    [ 5,   4,   1,   0,  -1,   0,   1,   3,   5,   5]
        }
    }

    /// The preset whose curve matches `gains` exactly, or nil ("Custom") when
    /// the user has nudged the sliders off any preset.
    static func matching(_ gains: [Double]) -> EqualizerPreset? {
        allCases.first { preset in
            let a = preset.gains, b = gains
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { abs($0 - $1) < 0.01 }
        }
    }
}

/// The persisted equalizer configuration: an on/off switch plus one gain (dB)
/// per band. A plain Sendable value so it can cross the actor boundary into the
/// audio thread on each change.
nonisolated struct EqualizerSettings: Sendable, Equatable, Codable {
    var isEnabled: Bool
    /// Per-band gain in dB; `EqualizerBands.count` entries, ordered low→high.
    var gains: [Double]

    static let flat = EqualizerSettings(
        isEnabled: false,
        gains: Array(repeating: 0, count: EqualizerBands.count)
    )

    /// Normalizes a possibly-malformed gains array (wrong length, out of range)
    /// to exactly `EqualizerBands.count` clamped entries. Guards against corrupt
    /// persisted data reaching the DSP.
    var normalizedGains: [Double] {
        (0..<EqualizerBands.count).map { i in
            let value = i < gains.count ? gains[i] : 0
            return min(max(value, EqualizerBands.gainRange.lowerBound),
                       EqualizerBands.gainRange.upperBound)
        }
    }
}

// MARK: - DSP

/// A normalized second-order (biquad) IIR filter section, Direct Form I. Holds
/// only coefficients — per-stream sample history lives in `BiquadState` so the
/// same coefficients can drive several channels.
nonisolated struct Biquad: Equatable {
    var b0: Double = 1, b1: Double = 0, b2: Double = 0
    var a1: Double = 0, a2: Double = 0

    /// The identity filter (passes the signal through untouched).
    static let identity = Biquad()

    /// RBJ cookbook "peaking EQ" section. At `frequency` the magnitude response
    /// equals `gainDB`; away from it the response returns to unity. A 0 dB gain
    /// yields the identity filter exactly.
    static func peaking(sampleRate: Double, frequency: Double, gainDB: Double, q: Double) -> Biquad {
        guard sampleRate > 0, frequency > 0, q > 0 else { return .identity }
        let a = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosw0 = cos(w0)
        let alpha = sin(w0) / (2 * q)

        let b0 = 1 + alpha * a
        let b1 = -2 * cosw0
        let b2 = 1 - alpha * a
        let a0 = 1 + alpha / a
        let a1 = -2 * cosw0
        let a2 = 1 - alpha / a

        return Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0,
                      a1: a1 / a0, a2: a2 / a0)
    }
}

/// One channel's running state for a single biquad section.
nonisolated struct BiquadState {
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    mutating func reset() { x1 = 0; x2 = 0; y1 = 0; y2 = 0 }

    /// Processes one sample through `c` (Direct Form I) and advances the state.
    mutating func process(_ x: Double, _ c: Biquad) -> Double {
        let y = c.b0 * x + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}

/// A thread-safe holder for the live `EqualizerSettings`. The main actor writes
/// it when the user changes a setting; the audio thread reads a snapshot on each
/// processing block. A monotonically increasing `version` lets the processor
/// detect changes and rebuild its coefficients only when needed.
nonisolated final class EqualizerSettingsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _settings: EqualizerSettings
    private var _version: UInt64 = 0

    init(_ settings: EqualizerSettings = .flat) {
        _settings = settings
    }

    var settings: EqualizerSettings {
        get { lock.lock(); defer { lock.unlock() }; return _settings }
        set {
            lock.lock()
            _settings = newValue
            _version &+= 1
            lock.unlock()
        }
    }

    /// Atomically reads the current settings and the version they were written
    /// at, so the caller can skip work when nothing changed.
    func snapshot() -> (settings: EqualizerSettings, version: UInt64) {
        lock.lock(); defer { lock.unlock() }
        return (_settings, _version)
    }
}

/// Filters interleaved or planar Float32 PCM through the band cascade. Created
/// per audio stream (so per-channel filter history doesn't leak between tracks)
/// and reads its gains from a shared `EqualizerSettingsBox`.
///
/// `process` runs on a realtime audio thread, so it allocates nothing on the hot
/// path: coefficients are rebuilt only when the box's version changes.
nonisolated final class EqualizerProcessor: @unchecked Sendable {
    private let box: EqualizerSettingsBox
    /// Optional spectrum meter fed the (channel-0) samples for the visualizer.
    /// Independent of whether EQ filtering is enabled.
    private let spectrum: SpectrumAnalyzer?
    private var sampleRate: Double = 44_100
    private var channelCount = 0
    private var enabled = false

    /// One coefficient set per band (shared across channels).
    private var coefficients: [Biquad] = []
    /// Per-channel, per-band filter history: `state[channel][band]`.
    private var state: [[BiquadState]] = []
    /// The box version the current coefficients were built from. Starts at a
    /// sentinel so the first `process` always builds.
    private var builtVersion: UInt64 = .max

    init(box: EqualizerSettingsBox, spectrum: SpectrumAnalyzer? = nil) {
        self.box = box
        self.spectrum = spectrum
    }

    /// Configures the processor for a stream's format. Resets all filter state.
    func prepare(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 44_100
        channelCount = max(0, channels)
        state = Array(
            repeating: Array(repeating: BiquadState(), count: EqualizerBands.count),
            count: channelCount
        )
        builtVersion = .max   // force a rebuild on the next block
        spectrum?.prepare(sampleRate: self.sampleRate)
    }

    /// Rebuilds coefficients from `gains` for the current sample rate.
    private func rebuild(gains: [Double]) {
        coefficients = zip(EqualizerBands.frequencies, gains).map { freq, gain in
            Biquad.peaking(sampleRate: sampleRate, frequency: freq, gainDB: gain, q: EqualizerBands.q)
        }
    }

    /// Refreshes coefficients from the box if the settings changed. Returns
    /// whether filtering should be applied at all (enabled with non-flat gains).
    private func syncIfNeeded() -> Bool {
        let (settings, version) = box.snapshot()
        if version != builtVersion {
            builtVersion = version
            enabled = settings.isEnabled
            rebuild(gains: settings.normalizedGains)
        }
        return enabled
    }

    /// Filters `frames` samples of one channel in place. `stride` is 1 for
    /// planar buffers and the channel count for interleaved ones; `offset` is
    /// the channel's starting index within an interleaved buffer.
    private func filter(_ samples: UnsafeMutablePointer<Float>, frames: Int,
                        stride: Int, offset: Int, channel: Int) {
        guard channel < state.count else { return }
        for frame in 0..<frames {
            let i = offset + frame * stride
            var value = Double(samples[i])
            for band in 0..<coefficients.count {
                value = state[channel][band].process(value, coefficients[band])
            }
            samples[i] = Float(value)
        }
    }

    /// Applies the equalizer to a planar buffer (one `channel` per call).
    func processPlanar(_ samples: UnsafeMutablePointer<Float>, frames: Int, channel: Int) {
        if channel == 0 { spectrum?.ingest(samples, frames: frames, stride: 1) }
        guard syncIfNeeded() else { return }
        filter(samples, frames: frames, stride: 1, offset: 0, channel: channel)
    }

    /// Applies the equalizer to an interleaved buffer carrying `channels`
    /// channels of `frames` frames each.
    func processInterleaved(_ samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        // Feed the meter the left channel (stride = channel count).
        spectrum?.ingest(samples, frames: frames, stride: max(1, channels))
        guard syncIfNeeded() else { return }
        for channel in 0..<channels {
            filter(samples, frames: frames, stride: channels, offset: channel, channel: channel)
        }
    }
}
