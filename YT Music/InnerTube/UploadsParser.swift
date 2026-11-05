//
//  UploadsParser.swift
//  YT Music
//

import Foundation

nonisolated enum UploadsParser {

    static func parse(_ response: BrowseResponse) -> [Shelf] {
        sections(in: response).compactMap(shelf(from:))
    }

    /// Handles both the single-column and two-column (`secondaryContents`) layouts.
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

    /// Only the selected tab carries content; the others are lazy continuations.
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

    private static func shelf(from section: BrowseResponse.SectionContent) -> Shelf? {
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

    private static func makeShelf(title: String, contents: [CarouselItem]?) -> Shelf? {
        let items = (contents ?? []).compactMap { HomeFeedParser.makeItem(from: $0) }
        guard !items.isEmpty else { return nil }
        return Shelf(title: title.isEmpty ? String(localized: "nav.uploads") : title, items: items)
    }
}
