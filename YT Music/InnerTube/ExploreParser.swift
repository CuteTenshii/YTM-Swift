//
//  ExploreParser.swift
//  YT Music
//
//

import Foundation

nonisolated enum ExploreParser {

    static func parse(_ response: BrowseResponse) -> [Shelf] {
        let sections = response.contents?
            .singleColumnBrowseResultsRenderer?
            .tabs?.first?
            .tabRenderer?.content?
            .sectionListRenderer?.contents ?? []

        return sections.compactMap(shelf(from:))
    }

    private static func shelf(from section: BrowseResponse.SectionContent) -> Shelf? {
        if let carousel = section.carousel {
            return makeShelf(
                title: carousel.title,
                contents: carousel.contents,
                buttons: HomeFeedParser.shelfButtons(from: carousel),
                rowsPerColumn: carousel.rowsPerColumn
            )
        }
        if let grid = section.gridRenderer {
            return makeShelf(title: grid.title, contents: grid.items)
        }
        return nil
    }

    private static func makeShelf(
        title: String,
        contents: [CarouselItem]?,
        buttons: [ShelfButton] = [],
        rowsPerColumn: Int = 1
    ) -> Shelf? {
        let items = (contents ?? []).compactMap { HomeFeedParser.makeItem(from: $0) }
        guard !items.isEmpty else { return nil }
        return Shelf(
            title: title.isEmpty ? "Explore" : title, items: items, buttons: buttons,
            rowsPerColumn: rowsPerColumn
        )
    }
}
