//
//  HomeFeedParser.swift
//  YT Music
//
//  Translates a raw InnerTube `BrowseResponse` into the clean `HomeFeed` model
//  the UI consumes. All the knowledge of YouTube's renderer quirks lives here.
//

import Foundation

nonisolated enum HomeFeedParser {

    static func parse(_ response: BrowseResponse) -> HomeFeed {
        let sections = response.contents?
            .singleColumnBrowseResultsRenderer?
            .tabs?.first?
            .tabRenderer?.content?
            .sectionListRenderer?.contents ?? []

        let shelves = sections.compactMap { shelf(from: $0) }
        return HomeFeed(shelves: shelves)
    }

    // MARK: - Shelves

    private static func shelf(from section: BrowseResponse.SectionContent) -> HomeShelf? {
        guard let carousel = section.carousel else { return nil }

        let items = (carousel.contents ?? []).compactMap { makeItem(from: $0) }
        guard !items.isEmpty else { return nil }

        let title = carousel.title.isEmpty ? "More" : carousel.title
        return HomeShelf(title: title, items: items)
    }

    /// Maps a single carousel/list entry to a `HomeItem`, dispatching on whichever
    /// card renderer it carries. Shared by the home, library, explore, and search
    /// parsers (all built from the same two row renderers).
    static func makeItem(from carouselItem: CarouselItem) -> HomeItem? {
        if let row = carouselItem.musicTwoRowItemRenderer {
            return makeItem(from: row)
        }
        if let row = carouselItem.musicResponsiveListItemRenderer {
            return makeItem(from: row)
        }
        return nil
    }

    // MARK: - Two-row cards

    static func makeItem(from row: MusicTwoRowItemRenderer) -> HomeItem? {
        let title = row.title?.text ?? ""
        guard !title.isEmpty else { return nil }

        let (kind, videoId, browseId, playlistId) = resolve(row.navigationEndpoint)
        let links = row.subtitle?.entityLinks ?? []

        return HomeItem(
            title: title,
            subtitle: row.subtitle?.text ?? "",
            thumbnailURL: row.thumbnailRenderer?.bestURL,
            kind: kind,
            videoId: videoId,
            browseId: browseId,
            playlistId: playlistId,
            artists: links.filter { $0.kind == .artist },
            albumLink: links.first { $0.kind == .album }
        )
    }

    // MARK: - List rows

    static func makeItem(from row: MusicResponsiveListItemRenderer) -> HomeItem? {
        let columns = row.textColumns
        guard let title = columns.first else { return nil }

        let subtitle = columns.dropFirst().joined(separator: " • ")
        let (kind, videoId, browseId, playlistId) = resolve(row.playEndpoint)
        let links = row.entityLinks

        return HomeItem(
            title: title,
            subtitle: subtitle,
            thumbnailURL: row.thumbnail?.bestURL,
            kind: kind,
            videoId: videoId,
            browseId: browseId,
            playlistId: playlistId,
            artists: links.filter { $0.kind == .artist },
            albumLink: links.first { $0.kind == .album }
        )
    }

    // MARK: - Endpoint resolution

    /// Builds a `HomeItem` from already-extracted text plus a navigation endpoint.
    /// Used for renderers that don't fit the two row shapes (e.g. the search
    /// top-result card), reusing the shared endpoint resolution.
    static func makeItem(
        title: String,
        subtitle: String,
        thumbnailURL: URL?,
        endpoint: NavigationEndpoint?
    ) -> HomeItem? {
        guard !title.isEmpty else { return nil }
        let (kind, videoId, browseId, playlistId) = resolve(endpoint)
        return HomeItem(
            title: title,
            subtitle: subtitle,
            thumbnailURL: thumbnailURL,
            kind: kind,
            videoId: videoId,
            browseId: browseId,
            playlistId: playlistId
        )
    }

    private static func resolve(
        _ endpoint: NavigationEndpoint?
    ) -> (HomeItem.Kind, String?, String?, String?) {
        if let watch = endpoint?.watchEndpoint, let videoId = watch.videoId {
            // A watch endpoint with a playlist is typically a music video / mix.
            let kind: HomeItem.Kind = watch.playlistId == nil ? .song : .video
            return (kind, videoId, nil, watch.playlistId)
        }

        if let browse = endpoint?.browseEndpoint, let browseId = browse.browseId {
            switch browse.pageType {
            case "MUSIC_PAGE_TYPE_ALBUM":    return (.album, nil, browseId, nil)
            case "MUSIC_PAGE_TYPE_PLAYLIST": return (.playlist, nil, browseId, nil)
            case "MUSIC_PAGE_TYPE_ARTIST":   return (.artist, nil, browseId, nil)
            default:                         return (.unknown, nil, browseId, nil)
            }
        }

        return (.unknown, nil, nil, nil)
    }
}
