//
//  CachedAsyncImage.swift
//  YT Music
//

import SwiftUI
import AppKit
import ImageIO

@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    /// Downsamples so the shorter side is at least `minPixelSize`; nil keeps the source resolution.
    func image(for url: URL, minPixelSize: Int?) async throws -> NSImage {
        let key = "\(minPixelSize ?? 0)|\(url.absoluteString)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let (data, _) = try await NetworkSession.shared.data(from: url)
        guard let cgImage = await Self.decode(data, minPixelSize: minPixelSize) else {
            throw URLError(.cannotDecodeContentData)
        }
        let image = NSImage(cgImage: cgImage, size: .zero)
        cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    @concurrent
    nonisolated private static func decode(_ data: Data, minPixelSize: Int?) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let minPixelSize,
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           min(width, height) > minPixelSize {
            let longSide = Double(max(width, height)) * Double(minPixelSize) / Double(min(width, height))
            options[kCGImageSourceThumbnailMaxPixelSize] = Int(longSide.rounded(.up))
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let pointSize: CGFloat?
    private let content: (AsyncImagePhase) -> Content

    @Environment(\.displayScale) private var displayScale
    @State private var phase: AsyncImagePhase = .empty

    /// `pointSize` is the side of the square the image fills; nil decodes at full resolution.
    init(url: URL?, pointSize: CGFloat? = nil, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.pointSize = pointSize
        self.content = content
    }

    init<I: View, P: View>(
        url: URL?,
        pointSize: CGFloat? = nil,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == AnyView {
        self.url = url
        self.pointSize = pointSize
        self.content = { phase in
            if case .success(let image) = phase {
                AnyView(content(image))
            } else {
                AnyView(placeholder())
            }
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            phase = .empty
            return
        }
        do {
            let minPixelSize = pointSize.map { Int(($0 * displayScale).rounded(.up)) }
            let image = try await ImageCache.shared.image(for: url, minPixelSize: minPixelSize)
            phase = .success(Image(nsImage: image))
        } catch {
            phase = .failure(error)
        }
    }
}
