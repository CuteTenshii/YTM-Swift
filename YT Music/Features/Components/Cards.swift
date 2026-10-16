//
//  Cards.swift
//  YT Music
//
//  The artwork card used inside shelves.
//

import SwiftUI
import AppKit

struct ItemCard<Extra: View>: View {
    @Environment(PlayerState.self) private var player
    let item: ShelfItem
    /// Screen-specific extra context-menu actions (e.g. "Delete upload").
    @ViewBuilder var extraMenu: Extra

    init(item: ShelfItem, @ViewBuilder extraMenu: () -> Extra = { EmptyView() }) {
        self.item = item
        self.extraMenu = extraMenu()
    }

    private let artworkSize: CGFloat = 160

    var body: some View {
        Group {
            if let destination = item.entityDestination {
                NavigationLink(value: destination) { card }
                    .buttonStyle(.plain)
            } else {
                Button(action: play) { card }
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
            likeStatus: item.likeStatus,
            extraActions: { extraMenu }
        )
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(
                url: item.thumbnailURL,
                circular: item.prefersCircularArtwork,
                size: artworkSize
            )
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(width: artworkSize, alignment: .leading)
        .contentShape(.rect)
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
