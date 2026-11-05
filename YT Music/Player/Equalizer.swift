//
//  Equalizer.swift
//  YT Music
//
//  Graphic equalizer: band layout, presets, settings, biquad DSP and processor (nonisolated).
//

import Foundation

/// Ten ISO octave-spaced center frequencies; the count sets every gain array's length.
nonisolated enum EqualizerBands {
    static let frequencies: [Double] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

    /// ~1.4 gives roughly one-octave bandwidth.
    static let q: Double = 1.41

    static let gainRange: ClosedRange<Double> = -12...12

    static var count: Int { frequencies.count }

    static func label(forIndex index: Int) -> String {
        let hz = frequencies[index]
        if hz >= 1_000 {
            let k = hz / 1_000
            return k == k.rounded() ? "\(Int(k))k" : String(format: "%.1fk", k)
        }
        return "\(Int(hz))"
    }
}

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
        case .flat:        [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bassBoost:   [ 6, 5, 4, 2, 0, 0, 0, 0, 0, 0]
        case .trebleBoost: [ 0, 0, 0, 0, 0, 1, 2, 4, 5, 6]
        case .vocal:       [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1]
        case .rock:        [ 4, 3, 1, -1, -1, 0, 2, 3, 4, 4]
        case .electronic:  [ 4, 3, 0, -1, -2, 1, 0, 2, 4, 5]
        case .loudness:    [ 5, 4, 1, 0, -1, 0, 1, 3, 5, 5]
        }
    }

    static func matching(_ gains: [Double]) -> EqualizerPreset? {
        allCases.first { preset in
            let a = preset.gains, b = gains
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { abs($0 - $1) < 0.01 }
        }
    }
}

nonisolated struct EqualizerSettings: Sendable, Equatable, Codable {
    var isEnabled: Bool
    var gains: [Double]

    static let flat = EqualizerSettings(
        isEnabled: false,
        gains: Array(repeating: 0, count: EqualizerBands.count)
    )

    /// Normalizes malformed gains to exactly `EqualizerBands.count` clamped entries.
    var normalizedGains: [Double] {
        (0..<EqualizerBands.count).map { i in
            let value = i < gains.count ? gains[i] : 0
            return min(max(value, EqualizerBands.gainRange.lowerBound),
                       EqualizerBands.gainRange.upperBound)
        }
    }
}

// MARK: - DSP

/// Normalized biquad section (Direct Form I); sample history lives in `BiquadState`.
nonisolated struct Biquad: Equatable {
    var b0: Double = 1, b1: Double = 0, b2: Double = 0
    var a1: Double = 0, a2: Double = 0

    static let identity = Biquad()

    /// RBJ cookbook peaking EQ; 0 dB gain yields the identity filter.
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

nonisolated struct BiquadState {
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    mutating func reset() { x1 = 0; x2 = 0; y1 = 0; y2 = 0 }

    mutating func process(_ x: Double, _ c: Biquad) -> Double {
        let y = c.b0 * x + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}

/// Thread-safe settings holder; `version` lets the processor rebuild coefficients only on change.
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

    func snapshot() -> (settings: EqualizerSettings, version: UInt64) {
        lock.lock(); defer { lock.unlock() }
        return (_settings, _version)
    }
}

/// Filters Float32 PCM through the band cascade; allocation-free on the realtime thread.
nonisolated final class EqualizerProcessor: @unchecked Sendable {
    private let box: EqualizerSettingsBox
    private let spectrum: SpectrumAnalyzer?
    private var sampleRate: Double = 44_100
    private var channelCount = 0
    private var enabled = false

    private var coefficients: [Biquad] = []
    private var state: [[BiquadState]] = []
    /// Starts at a sentinel so the first `process` always builds.
    private var builtVersion: UInt64 = .max

    init(box: EqualizerSettingsBox, spectrum: SpectrumAnalyzer? = nil) {
        self.box = box
        self.spectrum = spectrum
    }

    func prepare(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 44_100
        channelCount = max(0, channels)
        state = Array(
            repeating: Array(repeating: BiquadState(), count: EqualizerBands.count),
            count: channelCount
        )
        builtVersion = .max
        spectrum?.prepare(sampleRate: self.sampleRate)
    }

    private func rebuild(gains: [Double]) {
        coefficients = zip(EqualizerBands.frequencies, gains).map { freq, gain in
            Biquad.peaking(sampleRate: sampleRate, frequency: freq, gainDB: gain, q: EqualizerBands.q)
        }
    }

    /// Returns whether filtering applies (enabled with non-flat gains).
    private func syncIfNeeded() -> Bool {
        let (settings, version) = box.snapshot()
        if version != builtVersion {
            builtVersion = version
            enabled = settings.isEnabled
            rebuild(gains: settings.normalizedGains)
        }
        return enabled
    }

    /// `stride` is 1 for planar, channel count for interleaved; `offset` is the channel's start.
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

    func processPlanar(_ samples: UnsafeMutablePointer<Float>, frames: Int, channel: Int) {
        if channel == 0 { spectrum?.ingest(samples, frames: frames, stride: 1) }
        guard syncIfNeeded() else { return }
        filter(samples, frames: frames, stride: 1, offset: 0, channel: channel)
    }

    func processInterleaved(_ samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        // Feed the meter the left channel (stride = channel count).
        spectrum?.ingest(samples, frames: frames, stride: max(1, channels))
        guard syncIfNeeded() else { return }
        for channel in 0..<channels {
            filter(samples, frames: frames, stride: channels, offset: channel, channel: channel)
        }
    }
}
