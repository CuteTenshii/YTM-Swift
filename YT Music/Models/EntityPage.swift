//
//  EntityPage.swift
//  YT Music
//
//  View-facing models for an album / playlist / artist detail page, plus the
//  Hashable navigation value used to push one onto a NavigationStack.
//

import Foundation

/// Navigation value for pushing an entity detail page.
struct EntityDestination: Hashable {
    let browseId: String
    let kind: HomeItem.Kind
    /// Shown immediately (in the nav bar / header) while the page loads.
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
}

/// A named, navigable reference to an artist or album, extracted from the
/// navigation endpoints carried by a track row's text runs. Lets the now-playing
/// bar turn the artist/album into clickable links.
struct EntityLink: Hashable, Codable, Sendable {
    var name: String
    var browseId: String
    var kind: HomeItem.Kind

    /// A push destination for this link (no artwork/subtitle — the page fills
    /// those in once loaded).
    var destination: EntityDestination {
        EntityDestination(browseId: browseId, kind: kind, title: name, subtitle: "", thumbnailURL: nil)
    }
}

/// A fully-loaded album / playlist / artist page.
struct EntityPage: Sendable {
    var header: EntityHeader
    var tracks: [Track]
    var shelves: [HomeShelf]   // artist albums/singles/related, etc.

    /// A bare feed page (e.g. a shelf's "More" → "Listen again"): only carousels
    /// of cards, no entity of its own. Rendered as a titled list of shelves
    /// rather than with the big artwork/Play header an album/playlist gets.
    var isFeed: Bool {
        header.kind == .unknown && tracks.isEmpty
    }
}

struct EntityHeader: Sendable {
    var title: String
    var subtitle: String       // e.g. "Album • Artist • 2020"
    var description: String
    var thumbnailURL: URL?
    /// Wide banner artwork for artist pages (the immersive header's large
    /// background image). Nil for albums/playlists and artists without one.
    var bannerURL: URL? = nil
    var kind: HomeItem.Kind
    /// Navigable artist link(s) parsed from the header subtitle. For an album,
    /// these are the album's artist(s) — inherited by tracks that carry none.
    var artists: [EntityLink] = []
    /// Subscribe-button state for artist pages (nil for albums/playlists, or when
    /// signed out and the header carries no subscribe button).
    var subscription: ArtistSubscription? = nil
    /// The artist header's "Shuffle"/"Start radio" playlist id (e.g. `RDEM…`),
    /// when present — lets an artist page start a mix with no video seed.
    var radioPlaylistId: String? = nil

    var prefersCircularArtwork: Bool { kind == .artist }
}

/// The artist subscribe button's state and the InnerTube params needed to toggle
/// it. Parsed from the artist immersive header's `subscribeButtonRenderer`.
struct ArtistSubscription: Sendable, Equatable {
    var channelId: String
    var isSubscribed: Bool
    /// Opaque params for the subscribe / unsubscribe service endpoints.
    var subscribeParams: String?
    var unsubscribeParams: String?
}

/// A single playable track in a listing.
struct Track: Identifiable, Sendable {
    let id = UUID()
    var index: Int             // 1-based position in its listing
    var title: String
    var subtitle: String       // artist(s)
    var duration: String?      // "3:45"
    var thumbnailURL: URL?
    var videoId: String?
    /// Navigable artist links parsed from the row, if any.
    var artists: [EntityLink] = []
    /// Navigable album link parsed from the row, if any.
    var albumLink: EntityLink?
    /// History-removal feedback token, when this track came from the history page.
    var feedbackToken: String? = nil
    /// Playlist-scoped id for removing this row from an owned playlist, if known.
    var playlistSetVideoId: String? = nil
    /// The account's current like rating for this track, parsed from the row's
    /// menu when available (signed in). `.indifferent` when unknown — enough for
    /// a context menu to show the right "Like" / "Remove from Likes" label.
    var likeStatus: LikeStatus = .indifferent
}
