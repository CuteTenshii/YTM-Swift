//
//  ExploreParser.swift
//  YT Music
//
//  Parses the `FEmusic_explore` browse response into shelves. Explore uses the
//  same single-column layout and carousel/grid renderers as Home and Library
//  (new releases, charts, trending, top music videos), so we reuse `HomeShelf`
//  and `HomeFeedParser.makeItem`. The mood/genre chip grids (built from
//  `musicNavigationButtonRenderer`, which carries no card) yield no items and are
//  skipped.
//

import Foundation

nonisolated enum ExploreParser {

    static func parse(_ response: BrowseResponse) -> [HomeShelf] {
        let sections = response.contents?
            .singleColumnBrowseResultsRenderer?
            .tabs?.first?
            .tabRenderer?.content?
            .sectionListRenderer?.contents ?? []

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
        if let grid = section.gridRenderer {
            return makeShelf(title: grid.title, contents: grid.items)
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
        return HomeShelf(title: title.isEmpty ? "Explore" : title, items: items, buttons: buttons)
    }
}
