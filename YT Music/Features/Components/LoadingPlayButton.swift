//
//  LoadingPlayButton.swift
//  YT Music
//

import SwiftUI

/// Stands in for a circular play button while a track loads. Drawn from the
/// same circle glyph at the same size, so it keeps the button's footprint.
struct LoadingPlayButton: View {
    let size: CGFloat
    var color: Color = .primary

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: size))
            .foregroundStyle(color.opacity(0.2))
            .overlay { ProgressView().controlSize(.small).tint(color) }
            .accessibilityLabel("Loading")
    }
}
