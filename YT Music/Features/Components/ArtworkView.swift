//
//  ArtworkView.swift
//  YT Music
//
//  Artwork thumbnails, plus a type-erased shape so cards can switch between square and circular artwork.
//

import SwiftUI

struct ArtworkView: View {
    let url: URL?
    var circular: Bool = false
    let size: CGFloat

    var body: some View {
        CachedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(0.06), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
    }

    private var placeholder: some View {
        ZStack {
            Color.primary.opacity(0.08)
            Image(systemName: circular ? "person.fill" : "music.note")
                .font(.system(size: size * 0.3))
                .foregroundStyle(.primary.opacity(0.3))
        }
    }

    private var shape: AnyInsettableShape {
        circular
            ? AnyInsettableShape(Circle())
            : AnyInsettableShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Type-erased shape

/// Type-erased `InsettableShape` so artwork can swap between circle and rounded
/// rect while still using `strokeBorder`.
struct AnyInsettableShape: InsettableShape {
    private let pathBuilder: @Sendable (CGRect) -> Path
    private let insetBuilder: @Sendable (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        pathBuilder = { shape.path(in: $0) }
        insetBuilder = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path { pathBuilder(rect) }

    func inset(by amount: CGFloat) -> AnyInsettableShape { insetBuilder(amount) }
}
