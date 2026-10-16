//
//  FilterChipRow.swift
//  YT Music
//

import SwiftUI

/// A pill-shaped filter toggle. Selected = solid, otherwise a faint translucent fill.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
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

/// Horizontal row of selectable filter chips (YT Music style), optionally led by
/// an "All" chip (no filter, `nil`). Tapping the selected chip deselects it.
struct FilterChipRow<Chip: Identifiable & Equatable>: View {
    let chips: [Chip]
    let title: KeyPath<Chip, String>
    let selection: Chip?
    var showsAll = true
    let select: (Chip?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if showsAll {
                    FilterChip(title: "All", isSelected: selection == nil) { select(nil) }
                }
                ForEach(chips) { chip in
                    FilterChip(title: chip[keyPath: title], isSelected: chip == selection) {
                        select(chip == selection ? nil : chip)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }
}
