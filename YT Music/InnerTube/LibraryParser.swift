//
//  LibraryParser.swift
//  YT Music
//
//  Parses the `FEmusic_library_landing` browse response into shelves. The
//  library mixes grids (playlists/albums), carousels, and flat list shelves —
//  all built from the same card renderers as Home, so we reuse `HomeShelf` /
//  `HomeItem` and `HomeFeedParser.makeItem`.
//

import Foundation

nonisolated enum LibraryParser {

    static func parse(_ response: BrowseResponse) -> [HomeShelf] {
        let sections = response.contents?
            .singleColumnBrowseResultsRenderer?
            .tabs?.first?
            .tabRenderer?.content?
            .sectionListRenderer?.contents ?? []

        return sections.compactMap(shelf(from:))
    }

    private static func shelf(from section: BrowseResponse.SectionContent) -> HomeShelf? {
        if let grid = section.gridRenderer {
            return makeShelf(title: grid.title, contents: grid.items)
        }
        if let carousel = section.carousel {
            return makeShelf(title: carousel.title, contents: carousel.contents)
        }
        if let listShelf = section.listShelf {
            return makeShelf(title: listShelf.title?.text ?? "", contents: listShelf.contents)
        }
        return nil
    }

    private static func makeShelf(title: String, contents: [CarouselItem]?) -> HomeShelf? {
        let items = (contents ?? []).compactMap(item(from:))
        guard !items.isEmpty else { return nil }
        return HomeShelf(title: title.isEmpty ? "Library" : title, items: items)
    }

    private static func item(from carouselItem: CarouselItem) -> HomeItem? {
        if let row = carouselItem.musicTwoRowItemRenderer {
            return HomeFeedParser.makeItem(from: row)
        }
        if let row = carouselItem.musicResponsiveListItemRenderer {
            return HomeFeedParser.makeItem(from: row)
        }
        return nil
    }
}
