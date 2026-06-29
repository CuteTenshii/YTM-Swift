//
//  EntityPageParser.swift
//  YT Music
//
//  Maps a raw `EntityBrowseResponse` into the clean `EntityPage` model. Handles
//  album/playlist/artist headers (three renderer variants) and bodies in both
//  the single-column and newer two-column layouts.
//

import Foundation

nonisolated enum EntityPageParser {

    static func parse(_ response: EntityBrowseResponse, fallback: EntityDestination) -> EntityPage {
        let header = parseHeader(response.header, fallback: fallback)
        let sections = collectSections(response.contents)

        var tracks: [Track] = []
        var shelves: [HomeShelf] = []

        for section in sections {
            if let shelf = section.listShelf {
                tracks.append(contentsOf: parseTracks(shelf, startIndex: tracks.count + 1))
            } else if let carousel = section.carousel {
                if let shelf = makeShelf(from: carousel) { shelves.append(shelf) }
            }
        }

        return EntityPage(header: header, tracks: tracks, shelves: shelves)
    }

    // MARK: - Sections

    /// Gathers section content from whichever layout the response used.
    private static func collectSections(
        _ contents: EntityBrowseResponse.EntityContents?
    ) -> [BrowseResponse.SectionContent] {
        guard let contents else { return [] }
        var sections: [BrowseResponse.SectionContent] = []

        sections += sectionList(fromTabs: contents.singleColumnBrowseResultsRenderer?.tabs)

        if let two = contents.twoColumnBrowseResultsRenderer {
            sections += sectionList(fromTabs: two.tabs)
            sections += two.secondaryContents?.sectionListRenderer?.contents ?? []
        }

        return sections
    }

    private static func sectionList(
        fromTabs tabs: [BrowseResponse.Tab]?
    ) -> [BrowseResponse.SectionContent] {
        tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents ?? []
    }

    // MARK: - Header

    private static func parseHeader(
        _ container: EntityBrowseResponse.HeaderContainer?,
        fallback: EntityDestination
    ) -> EntityHeader {
        if let detail = container?.musicDetailHeaderRenderer {
            return EntityHeader(
                title: detail.title?.text ?? fallback.title,
                subtitle: joinNonEmpty(detail.subtitle?.text, detail.secondSubtitle?.text),
                description: detail.description?.text ?? "",
                thumbnailURL: detail.thumbnail?.croppedSquareThumbnailRenderer?.bestURL
                    ?? fallback.thumbnailURL,
                kind: fallback.kind
            )
        }

        if let responsive = container?.musicResponsiveHeaderRenderer {
            let subtitle = joinNonEmpty(
                responsive.straplineTextOne?.text,
                responsive.subtitle?.text,
                responsive.secondSubtitle?.text
            )
            return EntityHeader(
                title: responsive.title?.text ?? fallback.title,
                subtitle: subtitle.isEmpty ? fallback.subtitle : subtitle,
                description: responsive.description?.musicDescriptionShelfRenderer?
                    .description?.text ?? "",
                thumbnailURL: responsive.thumbnail?.musicThumbnailRenderer?.bestURL
                    ?? fallback.thumbnailURL,
                kind: fallback.kind
            )
        }

        if let immersive = container?.musicImmersiveHeaderRenderer {
            return EntityHeader(
                title: immersive.title?.text ?? fallback.title,
                subtitle: immersive.subtitle?.text ?? fallback.subtitle,
                description: immersive.description?.text ?? "",
                thumbnailURL: immersive.foregroundThumbnail?.musicThumbnailRenderer?.bestURL
                    ?? immersive.thumbnail?.musicThumbnailRenderer?.bestURL
                    ?? fallback.thumbnailURL,
                kind: fallback.kind
            )
        }

        // No recognizable header — fall back to what navigation gave us.
        return EntityHeader(
            title: fallback.title,
            subtitle: fallback.subtitle,
            description: "",
            thumbnailURL: fallback.thumbnailURL,
            kind: fallback.kind
        )
    }

    // MARK: - Tracks

    private static func parseTracks(
        _ shelf: MusicShelfRenderer,
        startIndex: Int
    ) -> [Track] {
        var index = startIndex
        return (shelf.contents ?? []).compactMap { item in
            guard let row = item.musicResponsiveListItemRenderer else { return nil }
            let columns = row.textColumns
            guard let title = columns.first else { return nil }

            defer { index += 1 }
            return Track(
                index: index,
                title: title,
                subtitle: columns.dropFirst().joined(separator: " • "),
                duration: row.durationText,
                thumbnailURL: row.thumbnail?.bestURL,
                videoId: row.trackVideoId
            )
        }
    }

    // MARK: - Carousels (reuse the Home shelf shape)

    private static func makeShelf(from carousel: MusicCarouselShelfRenderer) -> HomeShelf? {
        let items = (carousel.contents ?? []).compactMap(homeItem(from:))
        guard !items.isEmpty else { return nil }
        let title = carousel.title.isEmpty ? "More" : carousel.title
        return HomeShelf(title: title, items: items)
    }

    private static func homeItem(from carouselItem: CarouselItem) -> HomeItem? {
        if let row = carouselItem.musicTwoRowItemRenderer {
            return HomeFeedParser.makeItem(from: row)
        }
        if let row = carouselItem.musicResponsiveListItemRenderer {
            return HomeFeedParser.makeItem(from: row)
        }
        return nil
    }

    // MARK: - Helpers

    private static func joinNonEmpty(_ parts: String?...) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • ")
    }
}
