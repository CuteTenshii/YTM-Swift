//
//  SearchParser.swift
//  YT Music
//
//  Turns a raw `SearchResponse` into `HomeShelf`s the app already renders. The
//  default ("everything") search comes back as a flat, relevance-ranked list:
//  a `musicCardShelfRenderer` top result, then one `itemSectionRenderer` per
//  result row — no category headers. We re-group those rows by type (Songs,
//  Videos, Albums, Artists, Playlists, Podcasts, Episodes, Profiles) using the
//  rows' structural signals (`musicVideoType` / `pageType`), which are stable
//  across locales. Filtered searches that already arrive grouped (as titled
//  `musicShelfRenderer` shelves) keep their server titles.
//

import Foundation

/// A search scope the user can pick from the filter chips. `.all` is the default
/// relevance-ranked search (no scoping); the rest map to the `params` value the
/// YT Music web client sends to restrict results to one type.
nonisolated enum SearchFilter: String, CaseIterable, Identifiable, Sendable {
    case all, songs, videos, albums, artists, playlists, podcasts, episodes, profiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:       "All"
        case .songs:     "Songs"
        case .videos:    "Videos"
        case .albums:    "Albums"
        case .artists:   "Artists"
        case .playlists: "Playlists"
        case .podcasts:  "Podcasts"
        case .episodes:  "Episodes"
        case .profiles:  "Profiles"
        }
    }

    /// The InnerTube `search` `params` value scoping results to this filter — the
    /// (URL-encoded) protobuf blobs the web client sends. nil for `.all`, which
    /// sends no `params` and gets the default mixed feed.
    var params: String? {
        switch self {
        case .all:       nil
        case .songs:     "EgWKAQIIAWoMEA4QChADEAQQCRAF"
        case .videos:    "EgWKAQIQAWoMEA4QChADEAQQCRAF"
        case .albums:    "EgWKAQIYAWoMEA4QChADEAQQCRAF"
        case .artists:   "EgWKAQIgAWoMEA4QChADEAQQCRAF"
        case .playlists: "Eg-KAQwIABAAGAAgACgBMABqChAEEAMQCRAFEAo%3D"
        case .podcasts:  "EgWKAQJQAWoMEA4QChADEAQQCRAF"
        case .episodes:  "EgWKAQJIAWoMEA4QChADEAQQCRAF"
        case .profiles:  "EgWKAQJgAWoMEA4QChADEAQQCRAF"
        }
    }
}

/// A search result bucket. Order of `allCases` is the display order of the
/// category shelves.
nonisolated enum SearchCategory: CaseIterable {
    case song, video, album, artist, playlist, podcast, episode, profile, other

    var title: String {
        switch self {
        case .song:     "Songs"
        case .video:    "Videos"
        case .album:    "Albums"
        case .artist:   "Artists"
        case .playlist: "Playlists"
        case .podcast:  "Podcasts"
        case .episode:  "Episodes"
        case .profile:  "Profiles"
        case .other:    "More"
        }
    }

    /// Classifies a playable row by its `musicVideoType`.
    init(musicVideoType: String) {
        switch musicVideoType {
        case "MUSIC_VIDEO_TYPE_ATV":             self = .song
        case "MUSIC_VIDEO_TYPE_PODCAST_EPISODE": self = .episode
        default:                                 self = .video   // _OMV / _UGC / …
        }
    }

    /// Classifies a browsable row by its destination `pageType`.
    init(pageType: String) {
        switch pageType {
        case "MUSIC_PAGE_TYPE_ALBUM":        self = .album
        case "MUSIC_PAGE_TYPE_ARTIST":       self = .artist
        case "MUSIC_PAGE_TYPE_PLAYLIST":     self = .playlist
        case "MUSIC_PAGE_TYPE_USER_CHANNEL": self = .profile
        case "MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE", "MUSIC_PAGE_TYPE_PODCAST_SHOW":
            self = .podcast
        default:                             self = .other
        }
    }
}

nonisolated enum SearchParser {

    static func parse(_ response: SearchResponse) -> [HomeShelf] {
        let sections = response.contents?
            .tabbedSearchResultsRenderer?
            .tabs?.first?
            .tabRenderer?.content?
            .sectionListRenderer?.contents ?? []

        var topResult: HomeItem?
        var grouped: [HomeShelf] = []
        var byCategory: [SearchCategory: [HomeItem]] = [:]

        for section in sections {
            if let card = section.musicCardShelfRenderer {
                topResult = topResult ?? makeTopResult(card)
            } else if let listShelf = section.listShelf {
                // A pre-grouped, server-titled shelf (filtered search).
                if let shelf = makeShelf(title: listShelf.title?.text ?? "", contents: listShelf.contents) {
                    grouped.append(shelf)
                }
            } else if let carousel = section.carousel {
                if let shelf = makeShelf(title: carousel.title, contents: carousel.contents) {
                    grouped.append(shelf)
                }
            } else if let itemSection = section.itemSectionRenderer {
                // Ungrouped rows: classify each and collect by category.
                for carouselItem in itemSection.contents ?? [] {
                    guard let item = HomeFeedParser.makeItem(from: carouselItem) else { continue }
                    byCategory[category(for: carouselItem), default: []].append(stripType(item))
                }
            }
        }

        var shelves: [HomeShelf] = []
        if let topResult {
            shelves.append(HomeShelf(title: "Top result", items: [topResult]))
        }
        for category in SearchCategory.allCases {
            if let items = byCategory[category], !items.isEmpty {
                shelves.append(HomeShelf(title: category.title, items: items))
            }
        }
        shelves += grouped
        return shelves
    }

    // MARK: - Categorization

    /// Determines a result row's category from its structural signals: a watch
    /// endpoint's `musicVideoType` (songs/videos/episodes), else a browse
    /// endpoint's `pageType` (albums/artists/playlists/podcasts/profiles).
    private static func category(for carouselItem: CarouselItem) -> SearchCategory {
        if let row = carouselItem.musicResponsiveListItemRenderer {
            if let type = row.playEndpoint?.watchEndpoint?.musicVideoType {
                return SearchCategory(musicVideoType: type)
            }
            if let pageType = row.navigationEndpoint?.browseEndpoint?.pageType {
                return SearchCategory(pageType: pageType)
            }
            if row.trackVideoId != nil { return .song }
        }
        if let row = carouselItem.musicTwoRowItemRenderer {
            if let type = row.navigationEndpoint?.watchEndpoint?.musicVideoType {
                return SearchCategory(musicVideoType: type)
            }
            if let pageType = row.navigationEndpoint?.browseEndpoint?.pageType {
                return SearchCategory(pageType: pageType)
            }
        }
        return .other
    }

    // MARK: - Shelves

    private static func makeShelf(title: String, contents: [CarouselItem]?) -> HomeShelf? {
        let items = (contents ?? []).compactMap { HomeFeedParser.makeItem(from: $0).map(stripType) }
        guard !items.isEmpty else { return nil }
        return HomeShelf(title: title.isEmpty ? "Results" : title, items: items)
    }

    private static func makeTopResult(_ card: MusicCardShelfRenderer) -> HomeItem? {
        HomeFeedParser.makeItem(
            title: card.title?.text ?? "",
            subtitle: card.subtitle?.text ?? "",
            thumbnailURL: card.thumbnail?.bestURL,
            endpoint: card.onTap
        )
    }

    // MARK: - Subtitle cleanup

    /// Drops the leading content-type token ("Song" / "Album" / "Artist" / …)
    /// from a result's subtitle; the category shelf header already conveys the
    /// type, so repeating it on every row is noise.
    private static func stripType(_ item: HomeItem) -> HomeItem {
        var item = item
        var parts = item.subtitle.components(separatedBy: " • ")
        let labels: Set<String> = [
            "Song", "Video", "Episode", "Podcast",
            "Album", "Single", "EP", "Artist", "Playlist", "Profile",
        ]
        if parts.count > 1, let first = parts.first, labels.contains(first) {
            parts.removeFirst()
            item.subtitle = parts.joined(separator: " • ")
        }
        return item
    }
}
