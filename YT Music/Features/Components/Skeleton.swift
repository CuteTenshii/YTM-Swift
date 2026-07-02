//
//  Skeleton.swift
//  YT Music
//
//  Loading placeholders: a filled bar/box in the same grey as artwork
//  placeholders, plus a `.shimmering()` sweep applied once to a whole skeleton
//  layout so a page renders its final shape immediately while data loads.
//

import SwiftUI

// MARK: - Skeleton box

/// A solid placeholder block matching the artwork-placeholder grey. Used to
/// stand in for a piece of text, artwork, or a button in a loading layout.
struct SkeletonBox: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat = 6
    var circular: Bool = false

    var body: some View {
        Group {
            if circular {
                Circle().fill(Color.white.opacity(0.08))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Shimmer

/// A diagonal highlight that sweeps across the modified view forever. Apply once
/// to a full skeleton layout (not per box) so the whole page shimmers in sync.
private struct Shimmer: ViewModifier {
    @State private var animating = false

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    let width = geo.size.width
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.12), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: width)
                    .offset(x: animating ? width : -width)
                    .animation(
                        .linear(duration: 1.4).repeatForever(autoreverses: false),
                        value: animating
                    )
                }
                .allowsHitTesting(false)
            }
            .mask(content)
            .onAppear { animating = true }
    }
}

extension View {
    /// Sweeps a soft highlight across this view forever. Apply to a whole
    /// skeleton layout so its boxes shimmer together.
    func shimmering() -> some View {
        modifier(Shimmer())
    }
}
