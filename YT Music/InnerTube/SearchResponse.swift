//
//  SearchResponse.swift
//  YT Music
//
//  Decodable model for the InnerTube `search` endpoint. Search results arrive
//  under a `tabbedSearchResultsRenderer` rather than the `singleColumn…` wrapper
//  the home/library feeds use, but the shelves inside reuse the same renderers
//  (see BrowseResponse), so we decode their section list as the shared
//  `BrowseResponse.SectionContent`.
//
//  Response path:
//    contents
//      .tabbedSearchResultsRenderer
//      .tabs[0].tabRenderer.content
//      .sectionListRenderer.contents[]          <- "Songs" / "Albums" / … shelves
//        .musicShelfRenderer
//          .title.runs[].text                   <- shelf category
//          .contents[].musicResponsiveListItemRenderer
//

import Foundation

struct SearchResponse: Decodable {
    let contents: Contents?

    struct Contents: Decodable {
        let tabbedSearchResultsRenderer: Tabbed?
    }

    struct Tabbed: Decodable {
        let tabs: [BrowseResponse.Tab]?
    }
}
