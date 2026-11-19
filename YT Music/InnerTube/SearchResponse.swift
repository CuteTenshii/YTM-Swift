//
//  SearchResponse.swift
//  YT Music
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

struct SearchSuggestionsResponse: Decodable {
    let contents: [Section]?

    struct Section: Decodable {
        let searchSuggestionsSectionRenderer: SectionRenderer?
    }

    struct SectionRenderer: Decodable {
        let contents: [Content]?
    }

    struct Content: Decodable {
        let searchSuggestionRenderer: Renderer?
        let musicResponsiveListItemRenderer: MusicResponsiveListItemRenderer?
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

nonisolated struct SearchSuggestions: Sendable {
    var queries: [String] = []
    var items: [ShelfItem] = []
}

nonisolated enum SearchSuggestionsParser {
    static func parse(_ response: SearchSuggestionsResponse) -> SearchSuggestions {
        let contents = (response.contents ?? []).flatMap {
            $0.searchSuggestionsSectionRenderer?.contents ?? []
        }
        var seen = Set<String>()
        var result = SearchSuggestions()
        for content in contents {
            if let row = content.musicResponsiveListItemRenderer {
                if let item = HomeFeedParser.makeItem(from: row) { result.items.append(item) }
                continue
            }
            let renderer = content.searchSuggestionRenderer
            let text = renderer?.navigationEndpoint?.searchEndpoint?.query
                ?? renderer?.suggestion?.text
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(text).inserted else { continue }
            result.queries.append(text)
        }
        return result
    }
}
