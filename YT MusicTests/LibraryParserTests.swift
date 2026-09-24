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

        let shelves = LibraryParser.parse(response).shelves
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
        #expect(LibraryParser.parse(response).shelves.isEmpty)
    }

    @Test("Reads the header chips, whose browse sits inside a command executor")
    func parsesHeaderChips() throws {
        let response = try response(from: """
        { "contents": { "singleColumnBrowseResultsRenderer": { "tabs": [ { "tabRenderer": {
          "content": { "sectionListRenderer": {
            "header": { "musicSideAlignedItemRenderer": { "startItems": [ { "chipCloudRenderer": { "chips": [
              { "chipCloudChipRenderer": {
                "text": { "runs": [ { "text": "Playlists" } ] },
                "navigationEndpoint": { "commandExecutorCommand": { "commands": [
                  { "browseEndpoint": { "browseId": "FEmusic_liked_playlists" } }
                ] } }
              } },
              { "chipCloudChipRenderer": {
                "text": { "runs": [ { "text": "Profiles" } ] },
                "navigationEndpoint": { "commandExecutorCommand": { "commands": [
                  { "browseEndpoint": { "browseId": "FEmusic_library_user_profile_channels_list", "params": "ggMCCAc%3D" } }
                ] } }
              } }
            ] } } ] } },
            "contents": []
          } }
        } } ] } } }
        """)

        let chips = LibraryParser.parse(response).chips
        #expect(chips.map(\.title) == ["Playlists", "Profiles"])
        #expect(chips.map(\.browseId) == ["FEmusic_liked_playlists", "FEmusic_library_user_profile_channels_list"])
        #expect(chips.last?.params == "ggMCCAc%3D")
    }

    @Test("Parses a song listing as tracks, with its continuation, minus action tiles")
    func parsesContinuationAndDropsActionTiles() throws {
        let response = try response(from: """
        { "contents": { "singleColumnBrowseResultsRenderer": { "tabs": [ { "tabRenderer": {
          "content": { "sectionListRenderer": { "contents": [
            { "musicShelfRenderer": {
              "contents": [
                { "musicResponsiveListItemRenderer": {
                  "flexColumns": [ { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [ { "text": "Shuffle all" } ] } } } ],
                  "navigationEndpoint": { "watchPlaylistEndpoint": { "playlistId": "LM" } }
                } },
                { "musicResponsiveListItemRenderer": {
                  "flexColumns": [ { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [ { "text": "Some Song" } ] } } } ],
                  "playlistItemData": { "videoId": "vid1" }
                } }
              ],
              "continuations": [ { "nextContinuationData": { "continuation": "TOKEN1" } } ]
            } }
          ] } }
        } } ] } } }
        """)

        let page = LibraryParser.parse(response)
        #expect(page.shelves.isEmpty)
        #expect(page.tracks.map(\.title) == ["Some Song"])
        #expect(page.tracks.map(\.index) == [1])
        #expect(page.continuation == "TOKEN1")
    }

    @Test("Parses a grid continuation into one shelf with the next token")
    func parsesGridContinuation() throws {
        let response = try response(from: """
        { "continuationContents": { "gridContinuation": {
          "items": [
            { "musicTwoRowItemRenderer": {
              "title": { "runs": [ { "text": "Some Playlist" } ] },
              "navigationEndpoint": { "browseEndpoint": {
                "browseId": "VLPLabc",
                "browseEndpointContextSupportedConfigs": { "browseEndpointContextMusicConfig": { "pageType": "MUSIC_PAGE_TYPE_PLAYLIST" } }
              } }
            } }
          ],
          "continuations": [ { "nextContinuationData": { "continuation": "TOKEN2" } } ]
        } } }
        """)

        let page = LibraryParser.parseContinuation(response)
        #expect(page.shelves.flatMap(\.items).map(\.browseId) == ["VLPLabc"])
        #expect(page.continuation == "TOKEN2")
    }

    @Test("Parses a song list continuation as tracks; the last page has no token")
    func parsesListContinuation() throws {
        let response = try response(from: """
        { "continuationContents": { "musicShelfContinuation": {
          "contents": [
            { "musicResponsiveListItemRenderer": {
              "flexColumns": [ { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [ { "text": "Some Song" } ] } } } ],
              "playlistItemData": { "videoId": "vid2" }
            } }
          ]
        } } }
        """)

        let page = LibraryParser.parseContinuation(response)
        #expect(page.tracks.map(\.videoId) == ["vid2"])
        #expect(page.continuation == nil)
    }

    @Test("Appending a page renumbers its tracks and extends the last shelf")
    func appendsPages() {
        func track(_ id: String, _ index: Int) -> Track {
            Track(index: index, title: id, subtitle: "", duration: nil, thumbnailURL: nil, videoId: id)
        }
        func item(_ id: String) -> HomeItem {
            HomeItem(title: id, subtitle: "", thumbnailURL: nil, kind: .playlist,
                     videoId: nil, browseId: id, playlistId: nil)
        }
        let first = LibraryPage(shelves: [HomeShelf(title: "Library", items: [item("a")])],
                                tracks: [track("x", 1), track("y", 2)], continuation: "T1")
        let next = LibraryPage(shelves: [HomeShelf(title: "", items: [item("b")])],
                               tracks: [track("z", 1)], continuation: nil)

        let merged = first.appending(next)

        #expect(merged.shelves.count == 1)
        #expect(merged.shelves.first?.items.map(\.browseId) == ["a", "b"])
        #expect(merged.tracks.map(\.index) == [1, 2, 3])
        #expect(merged.continuation == nil)
    }
}
