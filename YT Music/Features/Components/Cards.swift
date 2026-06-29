//
//  Cards.swift
//  YT Music
//
//  Reusable building blocks shared by Home and entity pages: the horizontal
//  shelf, the artwork card, the right-click context menu, and a type-erased
//  shape so cards can switch between square and circular artwork.
//

import SwiftUI
import AppKit

// MARK: - Shelf

struct ShelfView: View {
    let shelf: HomeShelf

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)

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

// MARK: - Card

struct ItemCard: View {
    @Environment(PlayerState.self) private var player
    let item: HomeItem

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
            browseId: item.browseId
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
                .foregroundStyle(.white)
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
            videoId: videoId
        )
    }
}

// MARK: - Artwork

struct ArtworkView: View {
    let url: URL?
    var circular: Bool = false
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.06), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
    }

    private var placeholder: some View {
        ZStack {
            Color.white.opacity(0.08)
            Image(systemName: circular ? "person.fill" : "music.note")
                .font(.system(size: size * 0.3))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    private var shape: AnyInsettableShape {
        circular
            ? AnyInsettableShape(Circle())
            : AnyInsettableShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Context menu

private struct MusicContextMenu: ViewModifier {
    @Environment(PlayerState.self) private var player

    let title: String
    let subtitle: String
    let thumbnailURL: URL?
    let videoId: String?
    let playlistId: String?
    let browseId: String?

    private var link: URL? {
        MusicLinks.url(videoId: videoId, playlistId: playlistId, browseId: browseId)
    }

    func body(content: Content) -> some View {
        content.contextMenu {
            if let videoId {
                Button {
                    player.play(
                        title: title,
                        subtitle: subtitle,
                        thumbnailURL: thumbnailURL,
                        videoId: videoId
                    )
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                Button {
                    player.startRadio(
                        title: title,
                        subtitle: subtitle,
                        thumbnailURL: thumbnailURL,
                        videoId: videoId
                    )
                } label: {
                    Label("Start radio", systemImage: "antenna.radiowaves.left.and.right")
                }
            }

            if let link {
                Button {
                    NSWorkspace.shared.open(link)
                } label: {
                    Label("Open in YouTube Music", systemImage: "arrow.up.forward.app")
                }
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(link.absoluteString, forType: .string)
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            }
        }
    }
}

extension View {
    /// Adds the standard right-click menu (Play / Open / Copy link) for a music item.
    func musicContextMenu(
        title: String,
        subtitle: String,
        thumbnailURL: URL?,
        videoId: String?,
        playlistId: String?,
        browseId: String?
    ) -> some View {
        modifier(MusicContextMenu(
            title: title,
            subtitle: subtitle,
            thumbnailURL: thumbnailURL,
            videoId: videoId,
            playlistId: playlistId,
            browseId: browseId
        ))
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
