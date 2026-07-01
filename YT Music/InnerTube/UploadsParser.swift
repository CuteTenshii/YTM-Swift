//
//  UploadsParser.swift
//  YT Music
//
//  Parses the `FEmusic_library_privately_owned_landing` browse response — the
//  signed-in user's uploaded music — into shelves. Structurally identical to the
//  library landing: a grid of uploaded albums, a carousel of uploaded artists,
//  and a flat list shelf of uploaded songs, all built from the same card
//  renderers as Home, so we reuse `HomeShelf` / `HomeItem` and
//  `HomeFeedParser.makeItem`.
//

import Foundation

nonisolated enum UploadsParser {

    static func parse(_ response: BrowseResponse) -> [HomeShelf] {
        sections(in: response).compactMap(shelf(from:))
    }

    /// Uploaded music can come back in either the classic single-column layout or
    /// the newer two-column one (primary tab + `secondaryContents`), so collect
    /// sections from whichever the response uses.
    private static func sections(in response: BrowseResponse) -> [BrowseResponse.SectionContent] {
        if let single = response.contents?.singleColumnBrowseResultsRenderer {
            return sections(inTabs: single.tabs)
        }
        if let two = response.contents?.twoColumnBrowseResultsRenderer {
            var sections = sections(inTabs: two.tabs)
            sections += two.secondaryContents?.sectionListRenderer?.contents ?? []
            return sections
        }
        return []
    }

    /// Picks the meaningful tab's sections. This landing page returns several
    /// tabs (Library / Downloads / Uploads) where only the selected (Uploads) one
    /// carries content — the others are lazy `continuations` — so prefer the
    /// selected tab, then any tab that actually has sections, then the first.
    private static func sections(inTabs tabs: [BrowseResponse.Tab]?) -> [BrowseResponse.SectionContent] {
        let renderers = (tabs ?? []).compactMap(\.tabRenderer)
        func contents(_ renderer: BrowseResponse.TabRenderer) -> [BrowseResponse.SectionContent] {
            renderer.content?.sectionListRenderer?.contents ?? []
        }
        let chosen = renderers.first { $0.selected == true && !contents($0).isEmpty }
            ?? renderers.first { !contents($0).isEmpty }
            ?? renderers.first
        return chosen.map(contents) ?? []
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
        let items = (contents ?? []).compactMap { HomeFeedParser.makeItem(from: $0) }
        guard !items.isEmpty else { return nil }
        return HomeShelf(title: title.isEmpty ? "Uploads" : title, items: items)
    }
}
