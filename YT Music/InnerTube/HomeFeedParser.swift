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

        let items = (carousel.contents ?? []).compactMap(item(from:))
        guard !items.isEmpty else { return nil }

        let title = carousel.title.isEmpty ? "More" : carousel.title
        return HomeShelf(title: title, items: items)
    }

    private static func item(from carouselItem: CarouselItem) -> HomeItem? {
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

        return HomeItem(
            title: title,
            subtitle: row.subtitle?.text ?? "",
            thumbnailURL: row.thumbnailRenderer?.bestURL,
            kind: kind,
            videoId: videoId,
            browseId: browseId,
            playlistId: playlistId
        )
    }

    // MARK: - List rows

    static func makeItem(from row: MusicResponsiveListItemRenderer) -> HomeItem? {
        let columns = row.textColumns
        guard let title = columns.first else { return nil }

        let subtitle = columns.dropFirst().joined(separator: " • ")
        let (kind, videoId, browseId, playlistId) = resolve(row.playEndpoint)

        return HomeItem(
            title: title,
            subtitle: subtitle,
            thumbnailURL: row.thumbnail?.bestURL,
            kind: kind,
            videoId: videoId,
            browseId: browseId,
            playlistId: playlistId
        )
    }

    // MARK: - Endpoint resolution

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
