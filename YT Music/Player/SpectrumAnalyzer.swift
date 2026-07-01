//
//  SpectrumAnalyzer.swift
//  YT Music
//
//  A lightweight FFT spectrum meter for the immersive visualizer. It piggybacks
//  on the equalizer's audio tap (which already sees every item's decoded PCM):
//  the tap feeds one channel's samples in via `ingest` on the realtime audio
//  thread, we window + FFT each block with Accelerate, fold the bins into a few
//  log-spaced bands, and publish them behind a lock for the UI to read.
//
//  Like the equalizer DSP it's `nonisolated` so it runs off the main actor, and
//  the bin→band mapping is a pure function exercised in tests. The realtime
//  plumbing (as with the EQ tap) is the untested layer.
//

import Accelerate
import Foundation

nonisolated final class SpectrumAnalyzer: @unchecked Sendable {
    /// Number of bars the visualizer draws.
    let bandCount: Int
    private let fftSize: Int
    private let half: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup

    // Preallocated scratch — nothing is allocated on the audio thread.
    private let window: UnsafeMutablePointer<Float>
    private let input: UnsafeMutablePointer<Float>
    private let windowed: UnsafeMutablePointer<Float>
    private let realp: UnsafeMutablePointer<Float>
    private let imagp: UnsafeMutablePointer<Float>
    private let mags: UnsafeMutablePointer<Float>

    private var fill = 0
    private var sampleRate: Double = 44_100

    /// Guards `published` (and serializes the two taps that briefly overlap
    /// during a crossfade, so their `ingest` calls can't race the input buffer).
    private let lock = NSLock()
    private var published: [Float]

    init(bandCount: Int = 28, fftSize: Int = 1_024) {
        self.bandCount = bandCount
        self.fftSize = fftSize
        self.half = fftSize / 2
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

        window = .allocate(capacity: fftSize)
        input = .allocate(capacity: fftSize)
        windowed = .allocate(capacity: fftSize)
        realp = .allocate(capacity: half)
        imagp = .allocate(capacity: half)
        mags = .allocate(capacity: half)
        window.initialize(repeating: 0, count: fftSize)
        input.initialize(repeating: 0, count: fftSize)
        windowed.initialize(repeating: 0, count: fftSize)
        realp.initialize(repeating: 0, count: half)
        imagp.initialize(repeating: 0, count: half)
        mags.initialize(repeating: 0, count: half)
        published = [Float](repeating: 0, count: bandCount)

        vDSP_hann_window(window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        window.deallocate(); input.deallocate(); windowed.deallocate()
        realp.deallocate(); imagp.deallocate(); mags.deallocate()
    }

    /// Resets for a new stream's sample rate. Called from the tap's prepare.
    func prepare(sampleRate: Double) {
        lock.lock(); defer { lock.unlock() }
        self.sampleRate = sampleRate > 0 ? sampleRate : 44_100
        fill = 0
        for i in published.indices { published[i] = 0 }
    }

    /// The latest band levels (0…1, low→high frequency). Safe to call from any
    /// thread; the UI polls it each frame.
    func magnitudes() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return published
    }

    /// Feeds `frames` samples of one channel (interleaved buffers pass their
    /// channel count as `stride`). Accumulates a window and runs an FFT when full.
    func ingest(_ samples: UnsafePointer<Float>, frames: Int, stride: Int) {
        lock.lock(); defer { lock.unlock() }
        var i = 0
        while i < frames {
            let n = min(fftSize - fill, frames - i)
            for k in 0..<n { input[fill + k] = samples[(i + k) * stride] }
            fill += n; i += n
            if fill == fftSize { computeAndPublish(); fill = 0 }
        }
    }

    /// Windows the accumulated block, FFTs it, and folds the magnitudes into
    /// bands. Caller holds `lock`.
    private func computeAndPublish() {
        vDSP_vmul(input, 1, window, 1, windowed, 1, vDSP_Length(fftSize))

        var split = DSPSplitComplex(realp: realp, imagp: imagp)
        windowed.withMemoryRebound(to: DSPComplex.self, capacity: half) { c in
            vDSP_ctoz(c, 2, &split, 1, vDSP_Length(half))
        }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
        imagp[0] = 0   // drop the Nyquist term packed into imag[0]
        vDSP_zvabs(&split, 1, mags, 1, vDSP_Length(half))

        let bands = Self.mapBands(mags: mags, binCount: half,
                                  sampleRate: sampleRate, fftSize: fftSize,
                                  bandCount: bandCount)
        // Fast attack, slow decay so bars pop up and ease back down.
        for i in 0..<bandCount {
            published[i] = bands[i] > published[i] ? bands[i]
                                                   : published[i] * 0.80 + bands[i] * 0.20
        }
    }

    /// Folds `binCount` FFT magnitudes into `bandCount` log-spaced, level-scaled
    /// bands (0…1). Pure and deterministic — the tested seam.
    static func mapBands(mags: UnsafePointer<Float>, binCount: Int,
                         sampleRate: Double, fftSize: Int, bandCount: Int) -> [Float] {
        var out = [Float](repeating: 0, count: bandCount)
        guard binCount > 1, bandCount > 0 else { return out }

        let nyquist = sampleRate / 2
        let binHz = nyquist / Double(binCount)
        let minF = 40.0
        let maxF = max(minF * 2, min(16_000.0, nyquist))

        for b in 0..<bandCount {
            let f0 = minF * pow(maxF / minF, Double(b) / Double(bandCount))
            let f1 = minF * pow(maxF / minF, Double(b + 1) / Double(bandCount))
            let lo = max(1, min(binCount - 1, Int(f0 / binHz)))
            let hi = max(lo, min(binCount - 1, Int(f1 / binHz)))

            var sum: Float = 0
            for bin in lo...hi { sum += mags[bin] }
            let avg = sum / Float(hi - lo + 1)

            // Normalize by transform size, then log-compress to a 0…1 level.
            let norm = avg / Float(fftSize)
            let db = 20 * log10(norm + 1e-6)          // roughly -120…0 dB
            out[b] = min(max((db + 60) / 60, 0), 1)   // -60…0 dB → 0…1
        }
        return out
    }
}
