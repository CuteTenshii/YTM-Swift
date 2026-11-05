//
//  SearchParser.swift
//  YT Music
//

import Foundation

nonisolated enum SearchFilter: String, CaseIterable, Identifiable, Sendable {
    case all, songs, videos, albums, artists, playlists, podcasts, episodes, profiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:       String(localized: "search.filter.all")
        case .songs:     String(localized: "search.filter.songs")
        case .videos:    String(localized: "search.filter.videos")
        case .albums:    String(localized: "search.filter.albums")
        case .artists:   String(localized: "search.filter.artists")
        case .playlists: String(localized: "search.filter.playlists")
        case .podcasts:  String(localized: "search.filter.podcasts")
        case .episodes:  String(localized: "search.filter.episodes")
        case .profiles:  String(localized: "search.filter.profiles")
        }
    }

    /// URL-encoded protobuf `params` blob the web client sends; nil for `.all`.
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

nonisolated enum SearchCategory: CaseIterable {
    case song, video, album, artist, playlist, podcast, episode, profile, other

    var title: String {
        switch self {
        case .song:     String(localized: "search.filter.songs")
        case .video:    String(localized: "search.filter.videos")
        case .album:    String(localized: "search.filter.albums")
        case .artist:   String(localized: "search.filter.artists")
        case .playlist: String(localized: "search.filter.playlists")
        case .podcast:  String(localized: "search.filter.podcasts")
        case .episode:  String(localized: "search.filter.episodes")
        case .profile:  String(localized: "search.filter.profiles")
        case .other:    String(localized: "shelf.more")
        }
    }

    init(musicVideoType: String) {
        switch musicVideoType {
        case "MUSIC_VIDEO_TYPE_ATV":             self = .song
        case "MUSIC_VIDEO_TYPE_PODCAST_EPISODE": self = .episode
        default:                                 self = .video   // _OMV / _UGC / …
        }
    }

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

    static func parse(_ response: SearchResponse) -> [Shelf] {
        let sections = response.contents?
            .tabbedSearchResultsRenderer?
            .tabs?.first?
            .tabRenderer?.content?
            .sectionListRenderer?.contents ?? []

        var topResult: ShelfItem?
        var grouped: [Shelf] = []
        var byCategory: [SearchCategory: [ShelfItem]] = [:]

        for section in sections {
            if let card = section.musicCardShelfRenderer {
                topResult = topResult ?? makeTopResult(card)
            } else if let listShelf = section.listShelf {
                if let shelf = makeShelf(title: listShelf.title?.text ?? "", contents: listShelf.contents) {
                    grouped.append(shelf)
                }
            } else if let carousel = section.carousel {
                if let shelf = makeShelf(title: carousel.title, contents: carousel.contents) {
                    grouped.append(shelf)
                }
            } else if let itemSection = section.itemSectionRenderer {
                for carouselItem in itemSection.contents ?? [] {
                    guard let item = HomeFeedParser.makeItem(from: carouselItem) else { continue }
                    byCategory[category(for: carouselItem), default: []].append(stripType(item))
                }
            }
        }

        var shelves: [Shelf] = []
        if let topResult {
            shelves.append(Shelf(title: String(localized: "search.top_result"), items: [topResult]))
        }
        for category in SearchCategory.allCases {
            if let items = byCategory[category], !items.isEmpty {
                shelves.append(Shelf(title: category.title, items: items))
            }
        }
        shelves += grouped
        return shelves
    }

    // MARK: - Categorization

    /// Uses structural signals (`musicVideoType`, then `pageType`), which are stable across locales.
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

    private static func makeShelf(title: String, contents: [CarouselItem]?) -> Shelf? {
        let items = (contents ?? []).compactMap { HomeFeedParser.makeItem(from: $0).map(stripType) }
        guard !items.isEmpty else { return nil }
        return Shelf(title: title.isEmpty ? String(localized: "shelf.results") : title, items: items)
    }

    private static func makeTopResult(_ card: MusicCardShelfRenderer) -> ShelfItem? {
        HomeFeedParser.makeItem(
            title: card.title?.text ?? "",
            subtitle: card.subtitle?.text ?? "",
            thumbnailURL: card.thumbnail?.bestURL,
            endpoint: card.onTap
        )
    }

    // MARK: - Subtitle cleanup

    /// The category shelf header already conveys the content-type token.
    private static func stripType(_ item: ShelfItem) -> ShelfItem {
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
