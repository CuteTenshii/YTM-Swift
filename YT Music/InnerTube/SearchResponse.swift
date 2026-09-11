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

/// Lightweight suggestions returned while the search field is being edited.
struct SearchSuggestionsResponse: Decodable {
    let contents: [Content]?

    struct Content: Decodable {
        let searchSuggestionRenderer: Renderer?
    }

    struct Renderer: Decodable {
        let suggestion: Runs?
        let navigationEndpoint: Endpoint?
    }

    struct Runs: Decodable {
        let runs: [Run]?

        var text: String {
            runs?.map(\.text).joined() ?? ""
        }
    }

    struct Run: Decodable {
        let text: String
    }

    struct Endpoint: Decodable {
        let searchEndpoint: SearchEndpoint?
    }

    struct SearchEndpoint: Decodable {
        let query: String?
    }
}

nonisolated enum SearchSuggestionsParser {
    static func parse(_ response: SearchSuggestionsResponse) -> [String] {
        var seen = Set<String>()
        return (response.contents ?? []).compactMap { content in
            let renderer = content.searchSuggestionRenderer
            let text = renderer?.navigationEndpoint?.searchEndpoint?.query
                ?? renderer?.suggestion?.text
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(text).inserted else { return nil }
            return text
        }
    }
}
