//
//  EqualizerTests.swift
//  YT MusicTests
//
//  Tests for the equalizer: the biquad DSP (flat = passthrough, a peaking band
//  amplifies its center frequency by the requested dB), the settings model
//  (preset matching, gain normalization), and the settings → audio-engine
//  wiring through PlayerState. All network- and AVPlayer-free.
//

import Testing
import Foundation
@testable import YT_Music

// MARK: - Biquad DSP

@Suite("Equalizer DSP")
struct EqualizerDSPTests {

    /// Runs `samples` through one biquad section and returns the output.
    private func run(_ coefficients: Biquad, over samples: [Double]) -> [Double] {
        var state = BiquadState()
        return samples.map { state.process($0, coefficients) }
    }

    /// Peak absolute amplitude of the steady-state tail (after the filter settles).
    private func steadyAmplitude(_ samples: [Double]) -> Double {
        samples.suffix(samples.count / 2).map(abs).max() ?? 0
    }

    @Test("A 0 dB peaking filter is the identity")
    func flatIsIdentity() {
        let coefficients = Biquad.peaking(sampleRate: 44_100, frequency: 1_000, gainDB: 0, q: 1.41)
        #expect(abs(coefficients.b0 - 1) < 1e-9)
        #expect(abs(coefficients.b1 - coefficients.a1) < 1e-9)
        #expect(abs(coefficients.b2 - coefficients.a2) < 1e-9)

        let input = (0..<256).map { sin(2 * Double.pi * 440 * Double($0) / 44_100) }
        let output = run(coefficients, over: input)
        for (i, o) in zip(input, output) {
            #expect(abs(i - o) < 1e-9)
        }
    }

    @Test("A peaking boost amplifies its center frequency by the requested dB")
    func boostAmplifiesCenterFrequency() {
        let sampleRate = 44_100.0
        let frequency = 1_000.0
        let gainDB = 12.0
        let coefficients = Biquad.peaking(sampleRate: sampleRate, frequency: frequency,
                                          gainDB: gainDB, q: 1.41)

        // A long enough tone for the IIR to reach steady state.
        let input = (0..<8_000).map { sin(2 * Double.pi * frequency * Double($0) / sampleRate) }
        let output = run(coefficients, over: input)

        // At the center frequency the magnitude response equals the dB gain.
        let expectedRatio = pow(10, gainDB / 20)   // ~3.98×
        let ratio = steadyAmplitude(output) / steadyAmplitude(input)
        #expect(abs(ratio - expectedRatio) < 0.1)
    }

    @Test("A peaking cut attenuates its center frequency")
    func cutAttenuatesCenterFrequency() {
        let sampleRate = 44_100.0
        let frequency = 1_000.0
        let coefficients = Biquad.peaking(sampleRate: sampleRate, frequency: frequency,
                                          gainDB: -12, q: 1.41)
        let input = (0..<8_000).map { sin(2 * Double.pi * frequency * Double($0) / sampleRate) }
        let output = run(coefficients, over: input)
        let ratio = steadyAmplitude(output) / steadyAmplitude(input)
        #expect(ratio < 0.3)   // ~10^(-12/20) ≈ 0.25
    }

    @Test("Degenerate parameters fall back to the identity filter")
    func degenerateParametersAreIdentity() {
        #expect(Biquad.peaking(sampleRate: 0, frequency: 1_000, gainDB: 6, q: 1.41) == .identity)
        #expect(Biquad.peaking(sampleRate: 44_100, frequency: 0, gainDB: 6, q: 1.41) == .identity)
        #expect(Biquad.peaking(sampleRate: 44_100, frequency: 1_000, gainDB: 6, q: 0) == .identity)
    }
}

// MARK: - Processor

@Suite("EqualizerProcessor")
struct EqualizerProcessorTests {

    @Test("A disabled equalizer leaves samples untouched")
    func disabledPassesThrough() {
        let box = EqualizerSettingsBox(EqualizerSettings(
            isEnabled: false, gains: EqualizerPreset.bassBoost.gains))
        let processor = EqualizerProcessor(box: box)
        processor.prepare(sampleRate: 44_100, channels: 1)

        var samples: [Float] = (0..<512).map { Float(sin(2 * Double.pi * 60 * Double($0) / 44_100)) }
        let original = samples
        samples.withUnsafeMutableBufferPointer {
            processor.processPlanar($0.baseAddress!, frames: $0.count, channel: 0)
        }
        #expect(samples == original)
    }

    @Test("An enabled bass boost changes low-frequency samples")
    func enabledBoostAltersSignal() {
        let box = EqualizerSettingsBox(EqualizerSettings(
            isEnabled: true, gains: EqualizerPreset.bassBoost.gains))
        let processor = EqualizerProcessor(box: box)
        processor.prepare(sampleRate: 44_100, channels: 1)

        var samples: [Float] = (0..<4_000).map { Float(sin(2 * Double.pi * 64 * Double($0) / 44_100)) }
        let original = samples
        samples.withUnsafeMutableBufferPointer {
            processor.processPlanar($0.baseAddress!, frames: $0.count, channel: 0)
        }
        #expect(samples != original)
        // A boost should raise the peak amplitude of a 64 Hz tone.
        let before = original.map(abs).max() ?? 0
        let after = samples.suffix(2_000).map(abs).max() ?? 0
        #expect(after > before)
    }

    @Test("Live settings changes take effect on the next block")
    func picksUpSettingsChanges() {
        let box = EqualizerSettingsBox(.flat)
        let processor = EqualizerProcessor(box: box)
        processor.prepare(sampleRate: 44_100, channels: 1)

        // Flat: passthrough.
        var flat: [Float] = (0..<512).map { Float(sin(2 * Double.pi * 1_000 * Double($0) / 44_100)) }
        let original = flat
        flat.withUnsafeMutableBufferPointer {
            processor.processPlanar($0.baseAddress!, frames: $0.count, channel: 0)
        }
        #expect(flat == original)

        // Flip on a boost; the same processor should now alter the signal.
        box.settings = EqualizerSettings(isEnabled: true, gains: EqualizerPreset.trebleBoost.gains)
        var boosted: [Float] = (0..<512).map { Float(sin(2 * Double.pi * 8_000 * Double($0) / 44_100)) }
        let boostedOriginal = boosted
        boosted.withUnsafeMutableBufferPointer {
            processor.processPlanar($0.baseAddress!, frames: $0.count, channel: 0)
        }
        #expect(boosted != boostedOriginal)
    }
}

// MARK: - Settings model

@Suite("Equalizer settings")
@MainActor
struct EqualizerSettingsTests {

    private func freshSettings() -> AppSettings {
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return AppSettings(defaults: suite)
    }

    @Test("Defaults to a disabled, flat equalizer")
    func defaultsFlat() {
        let settings = freshSettings()
        #expect(settings.equalizerEnabled == false)
        #expect(settings.equalizerGains == EqualizerSettings.flat.gains)
    }

    @Test("Preset matching recognizes presets and reports Custom otherwise")
    func presetMatching() {
        #expect(EqualizerPreset.matching(EqualizerPreset.flat.gains) == .flat)
        #expect(EqualizerPreset.matching(EqualizerPreset.rock.gains) == .rock)
        var custom = EqualizerPreset.flat.gains
        custom[0] = 3
        #expect(EqualizerPreset.matching(custom) == nil)
    }

    @Test("Normalization clamps and resizes a malformed gains array")
    func normalizationClampsAndResizes() {
        let settings = EqualizerSettings(isEnabled: true, gains: [99, -99])
        let normalized = settings.normalizedGains
        #expect(normalized.count == EqualizerBands.count)
        #expect(normalized[0] == EqualizerBands.gainRange.upperBound)
        #expect(normalized[1] == EqualizerBands.gainRange.lowerBound)
        #expect(normalized[2] == 0)   // missing entries fill with 0
    }

    @Test("Applying a preset replaces every band gain")
    func applyingPreset() {
        let settings = freshSettings()
        settings.applyEqualizerPreset(.vocal)
        #expect(settings.equalizerGains == EqualizerPreset.vocal.gains)
    }

    @Test("Gains and enable state persist across instances")
    func persists() {
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let first = AppSettings(defaults: suite)
        first.equalizerEnabled = true
        first.applyEqualizerPreset(.loudness)

        let reloaded = AppSettings(defaults: suite)
        #expect(reloaded.equalizerEnabled == true)
        #expect(reloaded.equalizerGains == EqualizerPreset.loudness.gains)
    }

    @Test("Changing settings notifies the change handler")
    func notifiesOnChange() {
        let settings = freshSettings()
        var received: [EqualizerSettings] = []
        settings.onEqualizerChange = { received.append($0) }

        settings.equalizerEnabled = true
        settings.applyEqualizerPreset(.bassBoost)

        #expect(received.count == 2)
        #expect(received.last?.isEnabled == true)
        #expect(received.last?.gains == EqualizerPreset.bassBoost.gains)
    }
}

// MARK: - PlayerState wiring

@Suite("Equalizer wiring")
@MainActor
struct EqualizerWiringTests {

    private func settings() -> AppSettings {
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return AppSettings(defaults: suite)
    }

    @Test("PlayerState applies the persisted equalizer at startup")
    func appliesInitialEqualizer() {
        let audio = FakeAudioOutput()
        let s = settings()
        s.equalizerEnabled = true
        s.applyEqualizerPreset(.rock)

        let player = PlayerState(audio: audio, resolver: StubResolver(), settings: s)

        #expect(audio.equalizer?.isEnabled == true)
        #expect(audio.equalizer?.gains == EqualizerPreset.rock.gains)
        withExtendedLifetime(player) {}
    }

    @Test("Changing settings re-applies the equalizer to the audio engine")
    func reappliesOnChange() {
        let audio = FakeAudioOutput()
        let s = settings()
        let player = PlayerState(audio: audio, resolver: StubResolver(), settings: s)

        s.equalizerEnabled = true
        s.applyEqualizerPreset(.trebleBoost)

        #expect(audio.equalizer?.isEnabled == true)
        #expect(audio.equalizer?.gains == EqualizerPreset.trebleBoost.gains)
        withExtendedLifetime(player) {}
    }
}
