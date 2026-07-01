//
//  ArtworkPalette.swift
//  YT Music
//
//  Pulls a small palette of prominent colours out of cover art so the immersive
//  lyrics view can paint an ambient gradient tinted to the current track (the
//  way Apple Music does), instead of a flat blurred thumbnail.
//
//  The pixel-crunching is `nonisolated` and framework-agnostic (plain RGB, no
//  SwiftUI) so it can run off the main actor and the bucketing logic is unit
//  tested against synthetic pixel buffers.
//

import CoreGraphics
import Foundation
import ImageIO

/// One sampled colour, sRGB components in 0…1. Deliberately UI-agnostic.
nonisolated struct PaletteColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

nonisolated enum ArtworkPalette {
    /// Extracts up to `count` prominent, reasonably-distinct colours from encoded
    /// image data, favouring vibrant hues over the muddy grey a plain average
    /// produces. Returns `[]` when the data can't be decoded.
    static func extract(from data: Data, count: Int = 4, sampleSize: Int = 48) -> [PaletteColor] {
        guard let pixels = downsample(data, maxPixelSize: sampleSize) else { return [] }
        return palette(from: pixels, count: count)
    }

    /// Buckets RGBA8 pixels (`[r,g,b,a, r,g,b,a, …]`) into a coarse colour cube,
    /// scores each bucket by how much vibrant coverage it has, and returns the
    /// top `count` bucket centroids that are visually distinct from one another.
    static func palette(from pixels: [UInt8], count: Int, bins: Int = 6) -> [PaletteColor] {
        struct Bucket { var r = 0.0, g = 0.0, b = 0.0, weight = 0.0, n = 0.0 }
        var buckets: [Int: Bucket] = [:]

        var i = 0
        while i + 3 < pixels.count {
            defer { i += 4 }
            let a = Double(pixels[i + 3]) / 255
            guard a > 0.4 else { continue }
            let r = Double(pixels[i]) / 255
            let g = Double(pixels[i + 1]) / 255
            let b = Double(pixels[i + 2]) / 255

            // Vibrant, mid-bright pixels drive the palette; near-white and
            // near-black still count a little so monochrome art isn't empty.
            let sat = saturation(r, g, b)
            let bright = max(r, g, b)
            let vibrancy = 0.12 + sat * bright

            let key = bucketKey(r, g, b, bins: bins)
            var bucket = buckets[key] ?? Bucket()
            bucket.r += r; bucket.g += g; bucket.b += b
            bucket.weight += vibrancy; bucket.n += 1
            buckets[key] = bucket
        }

        let ranked = buckets.values
            .map { (color: PaletteColor(red: $0.r / $0.n, green: $0.g / $0.n, blue: $0.b / $0.n),
                    weight: $0.weight) }
            .sorted { $0.weight > $1.weight }

        // Greedily keep the heaviest buckets, skipping any too close to one we
        // already took, so the palette spans the art instead of clustering.
        var chosen: [PaletteColor] = []
        for candidate in ranked {
            if chosen.allSatisfy({ distanceSquared($0, candidate.color) > 0.02 }) {
                chosen.append(candidate.color)
                if chosen.count == count { break }
            }
        }
        return chosen
    }

    // MARK: - Helpers

    private static func saturation(_ r: Double, _ g: Double, _ b: Double) -> Double {
        let mx = max(r, g, b), mn = min(r, g, b)
        return mx <= 0 ? 0 : (mx - mn) / mx
    }

    private static func bucketKey(_ r: Double, _ g: Double, _ b: Double, bins: Int) -> Int {
        let rb = min(bins - 1, Int(r * Double(bins)))
        let gb = min(bins - 1, Int(g * Double(bins)))
        let bb = min(bins - 1, Int(b * Double(bins)))
        return (rb * bins + gb) * bins + bb
    }

    private static func distanceSquared(_ a: PaletteColor, _ b: PaletteColor) -> Double {
        let dr = a.red - b.red, dg = a.green - b.green, db = a.blue - b.blue
        return dr * dr + dg * dg + db * db
    }

    /// Decodes `data` to a small RGBA8 pixel buffer via ImageIO's thumbnail path
    /// (cheap, and downsamples in one step). Returns nil if decoding fails.
    private static func downsample(_ data: Data, maxPixelSize: Int) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pixels
    }
}
