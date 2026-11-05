//
//  EntityPage.swift
//  YT Music
//
//  View-facing models for an album / playlist / artist detail page, plus the
//  Hashable navigation value used to push one onto a NavigationStack.
//

import Foundation

struct EntityDestination: Hashable {
    let browseId: String
    let kind: ShelfItem.Kind
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
}

struct EntityLink: Hashable, Codable, Sendable {
    var name: String
    var browseId: String
    var kind: ShelfItem.Kind

    var destination: EntityDestination {
        EntityDestination(browseId: browseId, kind: kind, title: name, subtitle: "", thumbnailURL: nil)
    }
}

struct PlaylistFilter: Identifiable, Hashable, Sendable {
    var id: String { title }
    var title: String
    var token: String
    var clearToken: String?
    var isSelected = false
}

struct PlaylistSortOption: Identifiable, Hashable, Sendable {
    enum Action: Hashable, Sendable {
        case reload(String)
        case browse(browseId: String, params: String)
        case edit(PlaylistSortEdit)
    }

    var id: String { title }
    var title: String
    var action: Action
    var isSelected = false
}

struct EntityPage: Sendable {
    var header: EntityHeader
    var tracks: [Track]
    var shelves: [Shelf]
    var continuationToken: String? = nil
    var shufflePlaylistId: String? = nil
    var isManuallyOrdered = false
    var shareURL: URL? = nil
    var filters: [PlaylistFilter] = []
    var sortOptions: [PlaylistSortOption] = []

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
    var subtitle: String
    var description: String
    var thumbnailURL: URL?
    var artists: [EntityLink] = []
    var content: Content

    enum Content: Sendable {
        case artist(ArtistPageInfo)
        case profile(ArtistPageInfo)
        case album(CollectionInfo)
        case playlist(CollectionInfo)
        case podcast(PodcastInfo)
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

    var byline: EntityByline? {
        switch content {
        case .album(let info), .playlist(let info): info.byline
        case .podcast(let info): info.byline
        case .artist, .profile, .feed: nil
        }
    }

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

struct ArtistPageInfo: Sendable {
    var bannerURL: URL? = nil
    var monthlyAudience: String? = nil
    var pronouns: String? = nil
    var subscription: ArtistSubscription? = nil
    var radioPlaylistId: String? = nil
    var startRadioPlaylistId: String? = nil
}

struct CollectionInfo: Sendable {
    var privacy: PlaylistPrivacy? = nil
    var collaborationPanel: CollaborationPanelRef? = nil
    var voteOptions: [PlaylistVoteOption] = []
    var isSaved: Bool? = nil
    var byline: EntityByline? = nil
}

struct PodcastInfo: Sendable {
    var isSaved: Bool? = nil
    var byline: EntityByline? = nil
}

struct EntityByline: Sendable, Equatable {
    struct Run: Sendable, Equatable {
        var text: String
        var link: EntityLink?
    }

    var runs: [Run]
    var avatarURLs: [URL] = []
}

struct ArtistSubscription: Sendable, Equatable {
    var channelId: String
    var isSubscribed: Bool
    var subscribeParams: String?
    var unsubscribeParams: String?
    var isEnabled = true
}
