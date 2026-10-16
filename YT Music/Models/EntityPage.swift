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
    let kind: ShelfItem.Kind
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
    var kind: ShelfItem.Kind

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

/// A playlist sort order ("Newest first", "Title", …).
struct PlaylistSortOption: Identifiable, Hashable, Sendable {
    enum Action: Hashable, Sendable {
        /// Reloads the track list from a continuation token.
        case reload(String)
        /// Reloads the page with a different `params` (library artist sorts).
        case browse(browseId: String, params: String)
        /// Changes an owned playlist's saved order.
        case edit(PlaylistSortEdit)
    }

    var id: String { title }
    var title: String
    var action: Action
    var isSelected = false
}

/// A fully-loaded album / playlist / artist page.
struct EntityPage: Sendable {
    var header: EntityHeader
    var tracks: [Track]
    var shelves: [Shelf]   // artist albums/singles/related, etc.
    var continuationToken: String? = nil
    /// Playlist behind the page's "Shuffle all" row, when it has one.
    var shufflePlaylistId: String? = nil
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
    /// Navigable artist link(s) parsed from the header subtitle. For an album,
    /// these are the album's artist(s) — inherited by tracks that carry none.
    var artists: [EntityLink] = []
    var content: Content

    /// What the page is, with the fields only that type has.
    enum Content: Sendable {
        case artist(ArtistPageInfo)
        /// A plain YouTube channel (a song/video byline target).
        case profile(ArtistPageInfo)
        case album(CollectionInfo)
        case playlist(CollectionInfo)
        case podcast(PodcastInfo)
        /// A bare feed page with no entity of its own.
        case feed
    }

    var kind: ShelfItem.Kind {
        switch content {
        case .artist: .artist
        case .profile: .profile
        case .album: .album
        case .playlist: .playlist
        case .podcast: .podcast
        case .feed: .unknown
        }
    }

    var artistPage: ArtistPageInfo? {
        switch content {
        case .artist(let info), .profile(let info): info
        case .album, .playlist, .podcast, .feed: nil
        }
    }

    /// An album's artist(s), or the owner of a playlist or podcast show.
    var byline: EntityByline? {
        switch content {
        case .album(let info), .playlist(let info): info.byline
        case .podcast(let info): info.byline
        case .artist, .profile, .feed: nil
        }
    }

    /// Whether a playlist or show is saved to the library, when the header says.
    var isSaved: Bool? {
        switch content {
        case .album(let info), .playlist(let info): info.isSaved
        case .podcast(let info): info.isSaved
        case .artist, .profile, .feed: nil
        }
    }

    var collection: CollectionInfo? {
        get {
            switch content {
            case .album(let info), .playlist(let info): info
            case .artist, .profile, .podcast, .feed: nil
            }
        }
        set {
            guard let newValue else { return }
            switch content {
            case .album: content = .album(newValue)
            case .playlist: content = .playlist(newValue)
            case .artist, .profile, .podcast, .feed: break
            }
        }
    }

    var prefersCircularArtwork: Bool { kind == .artist || kind == .profile }
}

/// Header fields specific to artist and channel pages.
struct ArtistPageInfo: Sendable {
    /// Wide banner artwork (the immersive header's large background image).
    var bannerURL: URL? = nil
    /// "35.3M monthly audience".
    var monthlyAudience: String? = nil
    var pronouns: String? = nil
    /// Subscribe-button state (nil when signed out and the header carries no
    /// subscribe button).
    var subscription: ArtistSubscription? = nil
    /// The header's "Shuffle"/"Start radio" playlist id (e.g. `RDEM…`), when
    /// present — lets an artist page start a mix with no video seed.
    var radioPlaylistId: String? = nil
    /// The header's "Start radio" playlist id, when present.
    var startRadioPlaylistId: String? = nil
}

/// Header fields specific to album and playlist pages.
struct CollectionInfo: Sendable {
    /// The visibility of one of the user's own playlists, from its edit header.
    /// Nil for everything else.
    var privacy: PlaylistPrivacy? = nil
    /// Where to load one of the user's own playlists' collaboration settings.
    /// Nil when it can't be collaborative (private) or isn't the user's.
    var collaborationPanel: CollaborationPanelRef? = nil
    /// The choices for one of the user's playlists' "Voting" setting.
    var voteOptions: [PlaylistVoteOption] = []
    /// Whether the playlist is saved to the library, when the header says.
    var isSaved: Bool? = nil
    /// An album's artist(s) or a playlist's owner, shown with an avatar.
    var byline: EntityByline? = nil
}

/// Header fields specific to podcast show pages.
struct PodcastInfo: Sendable {
    var isSaved: Bool? = nil
    /// The publisher, with its avatar.
    var byline: EntityByline? = nil
}

/// Who made an album or playlist: its text runs (linked where the server gave
/// a destination) and avatars: a playlist's collaborators can bring up to three.
struct EntityByline: Sendable, Equatable {
    struct Run: Sendable, Equatable {
        var text: String
        var link: EntityLink?
    }

    var runs: [Run]
    var avatarURLs: [URL] = []
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
