//
//  LoadingPlayButton.swift
//  YT Music
//

import SwiftUI

struct LoadingPlayButton: View {
    let size: CGFloat
    var color: Color = .primary

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: size))
            .foregroundStyle(color.opacity(0.2))
            .overlay { ProgressView().controlSize(.small).tint(color) }
            .accessibilityLabel("common.loading")
    }
}
