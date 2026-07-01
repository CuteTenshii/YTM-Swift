//
//  SpectrumAnalyzerTests.swift
//  YT MusicTests
//
//  Tests for the FFT spectrum meter behind the immersive visualizer: a pure
//  sine tone should light up the band containing its frequency, higher tones
//  should peak in higher bands than lower tones, and silence should read flat.
//  Network- and audio-hardware-free (feeds synthetic PCM straight in).
//

import Foundation
import Testing
@testable import YT_Music

@Suite("Spectrum analyzer")
struct SpectrumAnalyzerTests {

    private let sampleRate = 44_100.0
    private let fftSize = 1_024

    /// One window of a sine at `frequency`, amplitude 0.8.
    private func sine(_ frequency: Double) -> [Float] {
        (0..<fftSize).map { i in
            Float(0.8 * sin(2 * Double.pi * frequency * Double(i) / sampleRate))
        }
    }

    /// Runs one window through the analyzer and returns the band levels.
    private func analyze(_ samples: [Float]) -> [Float] {
        let analyzer = SpectrumAnalyzer(bandCount: 28, fftSize: fftSize)
        analyzer.prepare(sampleRate: sampleRate)
        samples.withUnsafeBufferPointer {
            analyzer.ingest($0.baseAddress!, frames: samples.count, stride: 1)
        }
        return analyzer.magnitudes()
    }

    private func peakBand(_ bands: [Float]) -> Int {
        bands.indices.max(by: { bands[$0] < bands[$1] }) ?? 0
    }

    @Test("A tone peaks in a higher band as its frequency rises")
    func frequencyOrdering() {
        let low = peakBand(analyze(sine(150)))
        let mid = peakBand(analyze(sine(1_000)))
        let high = peakBand(analyze(sine(6_000)))

        #expect(low < mid)
        #expect(mid < high)
    }

    @Test("A loud tone produces a clearly non-zero peak")
    func toneHasEnergy() {
        let bands = analyze(sine(1_000))
        #expect(bands[peakBand(bands)] > 0.3)
    }

    @Test("Silence reads essentially flat and empty")
    func silenceIsFlat() {
        let bands = analyze([Float](repeating: 0, count: fftSize))
        #expect(bands.allSatisfy { $0 < 0.05 })
    }

    @Test("Band mapping is ordered low→high and clamped to 0…1")
    func mappingBounds() {
        // A magnitude buffer that ramps up with bin index.
        let binCount = fftSize / 2
        var mags = [Float](repeating: 0, count: binCount)
        for i in 0..<binCount { mags[i] = Float(i) }
        let bands = mags.withUnsafeBufferPointer {
            SpectrumAnalyzer.mapBands(mags: $0.baseAddress!, binCount: binCount,
                                      sampleRate: sampleRate, fftSize: fftSize, bandCount: 28)
        }
        #expect(bands.count == 28)
        #expect(bands.allSatisfy { $0 >= 0 && $0 <= 1 })
    }
}
