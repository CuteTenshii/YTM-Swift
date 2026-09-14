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

/// The same shelf as `ShelfView`, but its cards wrap onto multiple rows instead
/// of scrolling horizontally — used for full-page feeds (a shelf's "More") where
/// a single long horizontal strip reads poorly.
struct ShelfGridView: View {
    let shelf: HomeShelf
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
    let shelf: HomeShelf

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(shelf.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

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
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.white.opacity(0.1), in: Capsule())
        .contentShape(Capsule())
    }
}

// MARK: - Card

struct ItemCard<Extra: View>: View {
    @Environment(PlayerState.self) private var player
    let item: HomeItem
    /// Screen-specific extra context-menu actions (e.g. "Delete upload").
    @ViewBuilder var extraMenu: Extra

    init(item: HomeItem, @ViewBuilder extraMenu: () -> Extra = { EmptyView() }) {
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
            videoId: videoId,
            artists: item.artists,
            albumLink: item.albumLink
        )
    }
}

// MARK: - Artwork

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

/// A context-menu toggle that likes a track, or removes an existing like. The
/// rating comes from the row's parsed `likeStatus` (no extra request), or the
/// player's live/session rating when fresher. When the rating is genuinely
/// unknown (e.g. a "Listen again" feed card, which carries none) the entry is
/// omitted entirely rather than guessing "Like".
private struct LikeMenuButton: View {
    @Environment(PlayerState.self) private var player
    let videoId: String
    /// The rating parsed from this row's response, or nil when it carried none.
    let parsedStatus: LikeStatus?

    var body: some View {
        if let status = player.likeStatusIfKnown(for: videoId) ?? parsedStatus {
            let liked = status == .liked
            Button {
                player.setLikeStatus(for: videoId, to: liked ? .indifferent : .liked)
            } label: {
                Label(liked ? "Remove from Likes" : "Like",
                      systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
        }
    }
}

private struct MusicContextMenu<Extra: View>: ViewModifier {
    @Environment(PlayerState.self) private var player
    @Environment(Navigator.self) private var navigator
    @Environment(AuthStore.self) private var auth
    @Environment(PlaylistCoordinator.self) private var playlists

    let title: String
    let subtitle: String
    let thumbnailURL: URL?
    let videoId: String?
    let playlistId: String?
    let browseId: String?
    let artists: [EntityLink]
    let albumLink: EntityLink?
    /// The browsable page this item opens when it's an entity card (album /
    /// playlist / artist / podcast) rather than a playable track. Drives the
    /// menu's Play / Open entries.
    let entityDestination: EntityDestination?
    /// This track's current like rating, parsed from the row's response so the
    /// "Like" / "Remove from Likes" entry is labelled correctly. `nil` when the
    /// row carried no like info (e.g. a feed-page card), in which case it's
    /// resolved on demand when the menu opens.
    let likeStatus: LikeStatus?
    /// Screen-specific extra actions (e.g. "Remove from history", "Delete
    /// upload") appended below the standard entries. Built by the caller.
    let extraActions: Extra

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
                        videoId: videoId,
                        artists: artists,
                        albumLink: albumLink
                    )
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                Button {
                    player.playNext(
                        title: title,
                        subtitle: subtitle,
                        thumbnailURL: thumbnailURL,
                        videoId: videoId,
                        artists: artists,
                        albumLink: albumLink
                    )
                } label: {
                    Label("Play Next", systemImage: "text.insert")
                }

                Button {
                    player.startRadio(
                        title: title,
                        subtitle: subtitle,
                        thumbnailURL: thumbnailURL,
                        videoId: videoId,
                        artists: artists,
                        albumLink: albumLink
                    )
                } label: {
                    Label("Start radio", systemImage: "antenna.radiowaves.left.and.right")
                }

                if auth.isSignedIn {
                    LikeMenuButton(videoId: videoId, parsedStatus: likeStatus)

                    Button {
                        playlists.requestAdd(videoId: videoId, title: title)
                    } label: {
                        Label("Add to Playlist…", systemImage: "text.badge.plus")
                    }
                }
            } else if let entityDestination {
                entityActions(entityDestination)
            }

            goToArtist
            goToAlbum

            if let link {
                ShareLink(item: link)
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(link.absoluteString, forType: .string)
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            }

            extraActions
        }
    }

    /// Entity cards (album / playlist / artist / podcast) have no video of
    /// their own: offer to play the collection when it's queuable, and to open
    /// its page (what a left-click does).
    @ViewBuilder
    private func entityActions(_ destination: EntityDestination) -> some View {
        if let playlistId {
            Button {
                player.playAll(videoId: nil, playlistId: playlistId)
            } label: {
                Label("Play", systemImage: "play.fill")
            }
        }
        Button {
            navigator.open(destination)
        } label: {
            Label("Open", systemImage: "arrow.right")
        }
        .disabled(isCurrentPage(destination.browseId))
    }

    /// "Go to artist" for a single artist, or a submenu listing each when a track
    /// has several (e.g. "Artist 1", "Artist 2"). An entry is disabled when its
    /// page is already the one on screen.
    @ViewBuilder
    private var goToArtist: some View {
        if artists.count == 1, let artist = artists.first {
            Button {
                navigator.open(artist.destination)
            } label: {
                Label("Go to artist", systemImage: "music.mic")
            }
            .disabled(isCurrentPage(artist))
        } else if artists.count > 1 {
            Menu {
                ForEach(artists, id: \.self) { artist in
                    Button(artist.name) { navigator.open(artist.destination) }
                        .disabled(isCurrentPage(artist))
                }
            } label: {
                Label("Go to artist", systemImage: "music.mic")
            }
        }
    }

    @ViewBuilder
    private var goToAlbum: some View {
        if let albumLink {
            Button {
                navigator.open(albumLink.destination)
            } label: {
                Label("Go to album", systemImage: "square.stack")
            }
            .disabled(isCurrentPage(albumLink))
        }
    }

    /// Whether `link` points at the entity page currently on screen (in whichever
    /// tab's stack), so navigating there would be a no-op.
    private func isCurrentPage(_ link: EntityLink) -> Bool {
        isCurrentPage(link.browseId)
    }

    private func isCurrentPage(_ browseId: String) -> Bool {
        navigator.currentPath.last?.browseId == browseId
    }
}

extension View {
    /// Adds the standard right-click menu for a music item. Playable tracks
    /// (with a `videoId`) get Play / Play Next / Start radio / Like / Add to
    /// Playlist; entity cards (albums, playlists, artists, podcasts — pass
    /// their `entityDestination`) get Play / Open instead. Both kinds get
    /// "Go to artist"/"Go to album" when those links are known, Share / Copy
    /// Link, and any screen-specific `extraActions` appended at the bottom.
    func musicContextMenu<Extra: View>(
        title: String,
        subtitle: String,
        thumbnailURL: URL?,
        videoId: String?,
        playlistId: String?,
        browseId: String?,
        artists: [EntityLink] = [],
        albumLink: EntityLink? = nil,
        entityDestination: EntityDestination? = nil,
        likeStatus: LikeStatus? = nil,
        @ViewBuilder extraActions: () -> Extra = { EmptyView() }
    ) -> some View {
        modifier(MusicContextMenu(
            title: title,
            subtitle: subtitle,
            thumbnailURL: thumbnailURL,
            videoId: videoId,
            playlistId: playlistId,
            browseId: browseId,
            artists: artists,
            albumLink: albumLink,
            entityDestination: entityDestination,
            likeStatus: likeStatus,
            extraActions: extraActions()
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
