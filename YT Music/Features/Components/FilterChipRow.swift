//
//  FilterChipRow.swift
//  YT Music
//

import SwiftUI

/// Horizontal row of selectable filter chips (YT Music style): "All" (no
/// filter, `nil`) followed by `chips`.
struct FilterChipRow<Chip: Identifiable & Equatable>: View {
    let chips: [Chip]
    let title: KeyPath<Chip, String>
    let selection: Chip?
    let select: (Chip?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton("All", isSelected: selection == nil) { select(nil) }
                ForEach(chips) { chip in
                    chipButton(chip[keyPath: title], isSelected: chip == selection) { select(chip) }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func chipButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.primary : Color.primary.opacity(0.12))
                .foregroundStyle(isSelected ? Color.appBackground : Color.primary)
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}
