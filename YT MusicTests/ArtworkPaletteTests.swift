//
//  ArtworkPaletteTests.swift
//  YT MusicTests
//
//  Tests for the cover-art colour extractor that feeds the immersive lyrics
//  background: bucketing synthetic RGBA pixel buffers should surface the
//  dominant hues, keep them distinct, and favour vibrant colours over grey.
//

import Testing
@testable import YT_Music

@Suite("Artwork palette")
struct ArtworkPaletteTests {

    /// Builds an RGBA8 buffer by repeating each `(r,g,b)` colour `count` times.
    private func pixels(_ swatches: [(UInt8, UInt8, UInt8, Int)]) -> [UInt8] {
        var out: [UInt8] = []
        for (r, g, b, count) in swatches {
            for _ in 0..<count { out.append(contentsOf: [r, g, b, 255]) }
        }
        return out
    }

    @Test("Extracts the two dominant colours from a two-colour image")
    func twoColours() {
        let buffer = pixels([(220, 30, 30, 100), (30, 40, 220, 100)])
        let palette = ArtworkPalette.palette(from: buffer, count: 4)

        #expect(palette.count == 2)
        // One red-dominant, one blue-dominant colour, in either order.
        #expect(palette.contains { $0.red > 0.6 && $0.blue < 0.3 })
        #expect(palette.contains { $0.blue > 0.6 && $0.red < 0.3 })
    }

    @Test("Distinct colours aren't merged; near-duplicates are")
    func distinctness() {
        // Two nearly-identical reds plus a green: should collapse to ~2 colours.
        let buffer = pixels([(200, 20, 20, 80), (205, 25, 22, 80), (20, 200, 40, 80)])
        let palette = ArtworkPalette.palette(from: buffer, count: 4)

        #expect(palette.count == 2)
        #expect(palette.contains { $0.red > 0.6 })
        #expect(palette.contains { $0.green > 0.6 })
    }

    @Test("Vibrant colour outranks a larger grey area")
    func vibrancyBeatsGrey() {
        // Lots of mid-grey, a little vivid orange — orange should still lead.
        let buffer = pixels([(128, 128, 128, 300), (240, 120, 10, 60)])
        let palette = ArtworkPalette.palette(from: buffer, count: 2)

        #expect(!palette.isEmpty)
        let top = palette[0]
        #expect(top.red > top.blue && top.green > top.blue && top.red > 0.6)
    }

    @Test("Fully transparent pixels are ignored")
    func skipsTransparent() {
        // Transparent red + opaque blue → only blue survives.
        var buffer: [UInt8] = []
        for _ in 0..<100 { buffer.append(contentsOf: [220, 0, 0, 0]) }
        for _ in 0..<100 { buffer.append(contentsOf: [0, 0, 220, 255]) }
        let palette = ArtworkPalette.palette(from: buffer, count: 4)

        #expect(palette.count == 1)
        #expect(palette[0].blue > 0.6)
        #expect(palette[0].red < 0.2)
    }

    @Test("Empty buffer yields no colours")
    func empty() {
        #expect(ArtworkPalette.palette(from: [], count: 4).isEmpty)
    }
}
