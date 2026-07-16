//
//  HomeFeed.swift
//  YT Music
//
//  Clean, view-facing domain models for the Home feed. These are decoupled
//  from the raw InnerTube response shapes (see InnerTube/BrowseResponse.swift).
//

import Foundation

/// The whole home page: an ordered list of horizontal shelves.
struct HomeFeed: Sendable {
    var shelves: [HomeShelf]
}

/// One horizontal carousel, e.g. "Listen again" or "Mixed for you".
struct HomeShelf: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var items: [HomeItem]
    /// Tappable actions in the shelf header ("More", "Play all", …), parsed from
    /// the shelf's header buttons. Empty when the shelf carries none.
    var buttons: [ShelfButton] = []
}

/// A tappable action in a shelf header. YouTube shelves carry buttons beside the
/// title — a "More" link to a fuller listing, or a "Play all"-style play button.
struct ShelfButton: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var action: Action

    enum Action: Sendable, Hashable {
        /// Push a page (e.g. "More" → all of an artist's albums, a feed page).
        case navigate(EntityDestination)
        /// Play a playlist/album watch queue ("Play all"), optionally seeded at a
        /// specific video within it.
        case play(videoId: String?, playlistId: String)
    }
}

/// A single card inside a shelf.
struct HomeItem: Identifiable, Sendable {
    enum Kind: Sendable, Hashable, Codable {
        case song          // playable track
        case video         // music video
        case album
        case playlist
        case artist
        case unknown
    }

    let id = UUID()
    var title: String
    var subtitle: String
    var thumbnailURL: URL?
    var kind: Kind

    /// Set for songs/videos — the watch endpoint target.
    var videoId: String?
    /// Set for albums/playlists/artists — the browse endpoint target.
    var browseId: String?
    /// Set for playlists/albums that can be queued.
    var playlistId: String?

    /// Navigable artist links parsed from the row's byline, if any. Lets cards /
    /// rows offer "Go to artist" and render clickable artist names.
    var artists: [EntityLink] = []
    /// Navigable album link parsed from the row's byline, if any.
    var albumLink: EntityLink?
    /// Delete entity id for an uploaded item (uploaded song/album), enabling a
    /// "Delete upload" action. nil for everything that isn't a user upload.
    var deleteEntityId: String? = nil
    /// The account's current like rating for a song row, parsed from its menu
    /// when signed in. `nil` when the row carried no like info at all (e.g. a
    /// feed-page card) — distinct from a known `.indifferent` — so the UI can
    /// decide whether to resolve it on demand.
    var likeStatus: LikeStatus? = nil

    /// Artists render as circles; everything else as rounded squares.
    var prefersCircularArtwork: Bool { kind == .artist }

    /// A push destination if this item is a browsable page (album/playlist/
    /// artist/other browse), else nil (songs & videos play instead).
    var entityDestination: EntityDestination? {
        guard let browseId else { return nil }
        return EntityDestination(
            browseId: browseId,
            kind: kind,
            title: title,
            subtitle: subtitle,
            thumbnailURL: thumbnailURL
        )
    }
}
