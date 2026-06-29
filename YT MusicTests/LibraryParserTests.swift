//
//  LibraryParserTests.swift
//  YT MusicTests
//
//  Tests for parsing the library landing page (grids / shelves of cards).
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Library parser")
struct LibraryParserTests {

    private func response(from json: String) throws -> BrowseResponse {
        try JSONDecoder().decode(BrowseResponse.self, from: Data(json.utf8))
    }

    @Test("Parses a grid of playlists into a titled shelf")
    func parsesGrid() throws {
        let response = try response(from: """
        { "contents": { "singleColumnBrowseResultsRenderer": { "tabs": [ { "tabRenderer": {
          "content": { "sectionListRenderer": { "contents": [
            { "gridRenderer": {
              "header": { "gridHeaderRenderer": { "title": { "runs": [ { "text": "Playlists" } ] } } },
              "items": [
                { "musicTwoRowItemRenderer": {
                  "title": { "runs": [ { "text": "Liked Music" } ] },
                  "subtitle": { "runs": [ { "text": "Auto playlist" } ] },
                  "navigationEndpoint": { "browseEndpoint": {
                    "browseId": "VLLM",
                    "browseEndpointContextSupportedConfigs": { "browseEndpointContextMusicConfig": { "pageType": "MUSIC_PAGE_TYPE_PLAYLIST" } }
                  } }
                } }
              ]
            } }
          ] } }
        } } ] } } }
        """)

        let shelves = LibraryParser.parse(response)
        #expect(shelves.count == 1)
        #expect(shelves.first?.title == "Playlists")

        let item = try #require(shelves.first?.items.first)
        #expect(item.title == "Liked Music")
        #expect(item.kind == .playlist)
        #expect(item.browseId == "VLLM")
    }

    @Test("Skips empty sections")
    func skipsEmpty() throws {
        let response = try response(from: """
        { "contents": { "singleColumnBrowseResultsRenderer": { "tabs": [ { "tabRenderer": {
          "content": { "sectionListRenderer": { "contents": [ { "gridRenderer": { "items": [] } } ] } }
        } } ] } } }
        """)
        #expect(LibraryParser.parse(response).isEmpty)
    }
}
