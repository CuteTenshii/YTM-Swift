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
