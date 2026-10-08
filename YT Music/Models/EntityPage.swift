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

/// A playlist filter chip. Selecting it reloads the track list from `token`;
/// `clearToken` reloads the unfiltered list.
struct PlaylistFilter: Identifiable, Hashable, Sendable {
    var id: String { title }
    var title: String
    var token: String
    var clearToken: String?
    var isSelected = false
}

/// A playlist sort order ("Newest first", "Title", …). Selecting it reloads
/// the track list from `token`.
struct PlaylistSortOption: Identifiable, Hashable, Sendable {
    var id: String { title }
    var title: String
    var token: String
    var isSelected = false
}

/// A fully-loaded album / playlist / artist page.
struct EntityPage: Sendable {
    var header: EntityHeader
    var tracks: [Track]
    var shelves: [HomeShelf]   // artist albums/singles/related, etc.
    var continuationToken: String? = nil
    /// Whether the playlist's sort menu has "Manual ordering" selected, the
    /// only order in which its tracks can be rearranged.
    var isManuallyOrdered = false
    /// The page's official share URL (e.g. an album's `playlist?list=OLAK…`).
    var shareURL: URL? = nil
    /// A playlist's filter chips ("Party", "Chill", …), when it offers them.
    var filters: [PlaylistFilter] = []
    var sortOptions: [PlaylistSortOption] = []

    /// A bare feed page (e.g. a shelf's "More" → "Listen again"): only carousels
    /// of cards, no entity of its own. Rendered as a titled list of shelves
    /// rather than with the big artwork/Play header an album/playlist gets.
    var isFeed: Bool {
        header.kind == .unknown && tracks.isEmpty
    }

    func appending(_ next: EntityPage) -> EntityPage {
        EntityPage(
            header: header,
            tracks: tracks + next.tracks,
            shelves: shelves,
            continuationToken: next.continuationToken,
            isManuallyOrdered: isManuallyOrdered,
            shareURL: shareURL,
            filters: filters,
            sortOptions: sortOptions
        )
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
    /// The artist header's "Start radio" playlist id, when present.
    var startRadioPlaylistId: String? = nil
    /// The visibility of one of the user's own playlists, from its edit header.
    /// Nil for everything else.
    var privacy: PlaylistPrivacy? = nil
    /// Where to load one of the user's own playlists' collaboration settings.
    /// Nil when it can't be collaborative (private) or isn't the user's.
    var collaborationPanel: CollaborationPanelRef? = nil
    /// Whether the playlist is saved to the library, when the header says.
    var isSaved: Bool? = nil
    /// An album's artist(s) or a playlist's owner, shown with an avatar.
    var byline: EntityByline? = nil

    var prefersCircularArtwork: Bool { kind == .artist || kind == .profile }
}

/// Who made an album or playlist: its text runs (linked where the server gave
/// a destination) and an avatar.
struct EntityByline: Sendable, Equatable {
    struct Run: Sendable, Equatable {
        var text: String
        var link: EntityLink?
    }

    var runs: [Run]
    var avatarURL: URL?
}

/// The artist subscribe button's state and the InnerTube params needed to toggle
/// it. Parsed from the artist immersive header's `subscribeButtonRenderer`.
struct ArtistSubscription: Sendable, Equatable {
    var channelId: String
    var isSubscribed: Bool
    /// Opaque params for the subscribe / unsubscribe service endpoints.
    var subscribeParams: String?
    var unsubscribeParams: String?
    /// False when the server disables the button (the user's own channel).
    var isEnabled = true
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
    /// Note: this is plumbing, not permission — rows of *any* playlist may carry
    /// one. `canRemoveFromPlaylist` is the permission signal.
    var playlistSetVideoId: String? = nil
    /// The server's permission signal: this row's menu carried a
    /// remove-from-playlist action, which only rows of playlists the signed-in
    /// user can edit get. Gates both the row's "Remove from Playlist" entry
    /// and the page's edit affordances.
    var canRemoveFromPlaylist: Bool = false
    /// Additional text fields used by lightweight playlist search results.
    var searchTerms: [String] = []
    /// The account's current like rating for this track, parsed from the row's
    /// menu when available (signed in). `.indifferent` when unknown — enough for
    /// a context menu to show the right "Like" / "Remove from Likes" label.
    var likeStatus: LikeStatus = .indifferent
}
