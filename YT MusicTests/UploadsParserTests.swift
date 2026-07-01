//
//  UploadsParserTests.swift
//  YT MusicTests
//
//  Tests for parsing the uploaded-music landing page
//  (`FEmusic_library_privately_owned_landing`) into shelves of uploaded albums
//  and songs.
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Uploads parser")
struct UploadsParserTests {

    private func response(from json: String) throws -> BrowseResponse {
        try JSONDecoder().decode(BrowseResponse.self, from: Data(json.utf8))
    }

    @Test("Parses an uploaded-albums grid and an uploaded-songs list shelf")
    func parsesGridAndList() throws {
        let response = try response(from: """
        { "contents": { "singleColumnBrowseResultsRenderer": { "tabs": [ { "tabRenderer": {
          "content": { "sectionListRenderer": { "contents": [
            { "gridRenderer": {
              "header": { "gridHeaderRenderer": { "title": { "runs": [ { "text": "Albums" } ] } } },
              "items": [
                { "musicTwoRowItemRenderer": {
                  "title": { "runs": [ { "text": "My Album" } ] },
                  "subtitle": { "runs": [ { "text": "2024" } ] },
                  "navigationEndpoint": { "browseEndpoint": {
                    "browseId": "MPREb_upload123",
                    "browseEndpointContextSupportedConfigs": { "browseEndpointContextMusicConfig": { "pageType": "MUSIC_PAGE_TYPE_ALBUM" } }
                  } }
                } }
              ]
            } },
            { "musicShelfRenderer": {
              "title": { "runs": [ { "text": "Songs" } ] },
              "contents": [
                { "musicResponsiveListItemRenderer": {
                  "playlistItemData": { "videoId": "upload456" },
                  "flexColumns": [
                    { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [ { "text": "My Song" } ] } } },
                    { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [ { "text": "Me" } ] } } }
                  ]
                } }
              ]
            } }
          ] } }
        } } ] } } }
        """)

        let shelves = UploadsParser.parse(response)
        #expect(shelves.count == 2)

        let albums = try #require(shelves.first)
        #expect(albums.title == "Albums")
        #expect(albums.items.first?.title == "My Album")
        #expect(albums.items.first?.kind == .album)
        #expect(albums.items.first?.browseId == "MPREb_upload123")

        let songs = try #require(shelves.last)
        #expect(songs.title == "Songs")
        #expect(songs.items.first?.title == "My Song")
        #expect(songs.items.first?.videoId == "upload456")
    }

    @Test("Reads the selected Uploads tab, not an earlier empty tab")
    func picksSelectedTab() throws {
        // Mirrors the real landing page: Library/Downloads tabs are lazy (only
        // `continuations`), and the selected Uploads tab carries the grid.
        let response = try response(from: """
        { "contents": { "singleColumnBrowseResultsRenderer": { "tabs": [
          { "tabRenderer": { "title": "Library", "selected": false,
            "content": { "sectionListRenderer": { "continuations": [ { "x": 1 } ] } } } },
          { "tabRenderer": { "title": "Downloads", "selected": false,
            "content": { "sectionListRenderer": { "continuations": [ { "x": 1 } ] } } } },
          { "tabRenderer": { "title": "Uploads", "selected": true,
            "content": { "sectionListRenderer": { "contents": [
              { "gridRenderer": {
                "header": { "gridHeaderRenderer": { "title": { "runs": [ { "text": "Albums" } ] } } },
                "items": [
                  { "musicTwoRowItemRenderer": {
                    "title": { "runs": [ { "text": "Vendetta" } ] },
                    "subtitle": { "runs": [ { "text": "Album" } ] },
                    "navigationEndpoint": { "browseEndpoint": {
                      "browseId": "FEmusic_library_privately_owned_release_detailb_abc",
                      "browseEndpointContextSupportedConfigs": { "browseEndpointContextMusicConfig": { "pageType": "MUSIC_PAGE_TYPE_ALBUM" } }
                    } }
                  } }
                ]
              } }
            ] } } } }
        ] } } }
        """)

        let shelves = UploadsParser.parse(response)
        #expect(shelves.count == 1)
        #expect(shelves.first?.title == "Albums")
        #expect(shelves.first?.items.first?.kind == .album)
        #expect(shelves.first?.items.first?.browseId == "FEmusic_library_privately_owned_release_detailb_abc")
    }

    @Test("Falls back to \"Uploads\" when a shelf has no title")
    func titlelessShelfFallback() throws {
        let response = try response(from: """
        { "contents": { "singleColumnBrowseResultsRenderer": { "tabs": [ { "tabRenderer": {
          "content": { "sectionListRenderer": { "contents": [
            { "gridRenderer": {
              "items": [
                { "musicTwoRowItemRenderer": {
                  "title": { "runs": [ { "text": "Loose Track" } ] },
                  "navigationEndpoint": { "watchEndpoint": { "videoId": "abc" } }
                } }
              ]
            } }
          ] } }
        } } ] } } }
        """)

        let shelves = UploadsParser.parse(response)
        #expect(shelves.first?.title == "Uploads")
    }

    @Test("Skips shelves with no items and returns empty for a blank page")
    func skipsEmpty() throws {
        let response = try response(from: """
        { "contents": { "singleColumnBrowseResultsRenderer": { "tabs": [ { "tabRenderer": {
          "content": { "sectionListRenderer": { "contents": [
            { "gridRenderer": { "items": [] } }
          ] } }
        } } ] } } }
        """)
        #expect(UploadsParser.parse(response).isEmpty)
    }
}
