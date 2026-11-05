//
//  RelatedParser.swift
//  YT Music
//

import Foundation

nonisolated enum RelatedParser {

    static func parse(_ response: BrowseResponse) -> [Shelf] {
        let sections = response.contents?.sectionListRenderer?.contents ?? []
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
        if let listShelf = section.listShelf {
            return makeShelf(title: listShelf.title?.text ?? "", contents: listShelf.contents)
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
            title: title.isEmpty ? "Related" : title, items: items, buttons: buttons,
            rowsPerColumn: rowsPerColumn
        )
    }
}
