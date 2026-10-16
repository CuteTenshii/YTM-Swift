//
//  ShelfViews.swift
//  YT Music
//
//  The horizontal shelf, its row-grid and chart layouts, header and header buttons.
//

import SwiftUI

struct ShelfView: View {
    let shelf: Shelf

    var body: some View {
        if let rows = shelf.gridRows {
            RowGridShelfView(shelf: shelf, rowsPerColumn: rows)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ShelfHeader(shelf: shelf)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(shelf.items) { item in
                            ItemCard(item: item)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }
}

/// A grid shelf ("Quick picks", charts): horizontally scrolling columns of
/// compact rows, chart rows led by their rank and trend arrow.
private struct RowGridShelfView: View {
    let shelf: Shelf
    let rowsPerColumn: Int

    private var columns: [[ShelfItem]] {
        stride(from: 0, to: shelf.items.count, by: rowsPerColumn).map {
            Array(shelf.items[$0..<min($0 + rowsPerColumn, shelf.items.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShelfHeader(shelf: shelf)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(columns, id: \.first?.id) { column in
                        VStack(spacing: 0) {
                            ForEach(column) { item in
                                ShelfRow(item: item)
                            }
                        }
                        .frame(width: 340)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

private struct ShelfRow: View {
    @Environment(PlayerState.self) private var player
    let item: ShelfItem

    @State private var hovering = false

    private var isCurrent: Bool {
        item.videoId != nil && item.videoId == player.nowPlaying?.videoId
    }

    var body: some View {
        Group {
            if let destination = item.entityDestination {
                NavigationLink(value: destination) { row }
                    .buttonStyle(.plain)
            } else {
                Button(action: play) { row }
                    .buttonStyle(.plain)
            }
        }
        .musicContextMenu(
            title: item.title,
            subtitle: item.subtitle,
            thumbnailURL: item.thumbnailURL,
            videoId: item.videoId,
            playlistId: item.playlistId,
            browseId: item.browseId,
            artists: item.artists,
            albumLink: item.albumLink,
            entityDestination: item.entityDestination,
            likeStatus: item.likeStatus
        )
    }

    private var row: some View {
        HStack(spacing: 12) {
            if let chartRank = item.chartRank {
                RankLabel(chartRank: chartRank)
            }

            ArtworkView(url: item.thumbnailURL, circular: item.prefersCircularArtwork, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? Color.red : .primary)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .clipShape(.rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { hovering = $0 }
    }

    private func play() {
        guard let videoId = item.videoId else { return }
        player.play(
            title: item.title,
            subtitle: item.subtitle,
            thumbnailURL: item.thumbnailURL,
            videoId: videoId,
            artists: item.artists,
            albumLink: item.albumLink
        )
    }
}

private struct RankLabel: View {
    let chartRank: ChartRank

    var body: some View {
        VStack(spacing: 2) {
            Text(chartRank.rank)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
            if let trend = chartRank.trend {
                trendIcon(trend)
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .frame(width: 28)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func trendIcon(_ trend: ChartRank.Trend) -> some View {
        switch trend {
        case .up:
            Image(systemName: "arrowtriangle.up.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Up")
        case .down:
            Image(systemName: "arrowtriangle.down.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Down")
        case .neutral:
            Image(systemName: "circle.fill")
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .accessibilityLabel("No change")
        }
    }
}

/// The same shelf as `ShelfView`, but its cards wrap onto multiple rows instead
/// of scrolling horizontally — used for full-page feeds (a shelf's "More") where
/// a single long horizontal strip reads poorly.
struct ShelfGridView: View {
    let shelf: Shelf
    /// Hidden for a feed's sole shelf, whose title only repeats the page title.
    var showsHeader = true

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                ShelfHeader(shelf: shelf)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(shelf.items) { item in
                    ItemCard(item: item)
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

/// A shelf's title row plus any header action pills ("More", "Play all").
private struct ShelfHeader: View {
    let shelf: Shelf

    var body: some View {
        HStack(alignment: shelf.avatarURL == nil ? .firstTextBaseline : .center, spacing: 12) {
            if let avatarURL = shelf.avatarURL {
                ArtworkView(url: avatarURL, circular: true, size: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                if !shelf.strapline.isEmpty {
                    Text(shelf.strapline)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(shelf.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 12)

            ForEach(shelf.buttons) { button in
                ShelfButtonView(button: button)
            }
        }
        .padding(.horizontal, 24)
    }
}

/// A shelf-header action pill. "More" (a browse endpoint) pushes a fuller
/// listing; "Play all" and similar watch-endpoint buttons start playback.
private struct ShelfButtonView: View {
    @Environment(PlayerState.self) private var player
    let button: ShelfButton

    var body: some View {
        switch button.action {
        case .navigate(let destination):
            NavigationLink(value: destination) { pill }
                .buttonStyle(.plain)
        case .play(let videoId, let playlistId):
            Button {
                player.playAll(videoId: videoId, playlistId: playlistId)
            } label: {
                pill
            }
            .buttonStyle(.plain)
        }
    }

    private var pill: some View {
        HStack(spacing: 5) {
            if case .play = button.action {
                Image(systemName: "play.fill")
                    .font(.caption)
            }
            Text(button.title)
            if case .navigate = button.action {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary.opacity(0.85))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.primary.opacity(0.1), in: Capsule())
        .contentShape(Capsule())
    }
}
