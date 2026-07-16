//
//  RelatedParser.swift
//  YT Music
//
//  Parses the watch-next "Related" browse response into shelves. Unlike Home /
//  Explore (which nest their shelves under a tab), the related page returns its
//  section list directly under `contents.sectionListRenderer`. The shelves
//  themselves use the same carousel / list renderers, so we reuse `HomeShelf`
//  and `HomeFeedParser.makeItem`. Non-card sections (e.g. the description shelf
//  and the "About the artist" text block) carry no items and are skipped.
//

import Foundation

nonisolated enum RelatedParser {

    static func parse(_ response: BrowseResponse) -> [HomeShelf] {
        let sections = response.contents?.sectionListRenderer?.contents ?? []
        return sections.compactMap(shelf(from:))
    }

    private static func shelf(from section: BrowseResponse.SectionContent) -> HomeShelf? {
        if let carousel = section.carousel {
            return makeShelf(
                title: carousel.title,
                contents: carousel.contents,
                buttons: HomeFeedParser.shelfButtons(from: carousel)
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
        buttons: [ShelfButton] = []
    ) -> HomeShelf? {
        let items = (contents ?? []).compactMap { HomeFeedParser.makeItem(from: $0) }
        guard !items.isEmpty else { return nil }
        return HomeShelf(title: title.isEmpty ? "Related" : title, items: items, buttons: buttons)
    }
}
