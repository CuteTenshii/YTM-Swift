//
//  ExploreParserTests.swift
//  YT MusicTests
//
//  Verifies explore parsing against a fixture shaped like the real
//  `FEmusic_explore` browse response (no network): a carousel of new releases,
//  plus a mood/genre chip grid that should be skipped (its buttons carry no card).
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Explore parser")
struct ExploreParserTests {

    private let fixture = """
    {"contents":{"singleColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
      {"musicCarouselShelfRenderer":{
        "header":{"musicCarouselShelfBasicHeaderRenderer":{
          "title":{"runs":[{"text":"New albums & singles"}]},
          "moreContentButton":{"buttonRenderer":{
            "text":{"runs":[{"text":"More"}]},
            "navigationEndpoint":{"browseEndpoint":{
              "browseId":"FEmusic_new_releases_albums",
              "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_PLAYLIST"}}
            }}
          }}
        }},
        "contents":[
          {"musicTwoRowItemRenderer":{
            "title":{"runs":[{"text":"Some Album"}]},
            "subtitle":{"runs":[{"text":"Some Artist"}]},
            "navigationEndpoint":{"browseEndpoint":{
              "browseId":"MPREb_xyz",
              "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ALBUM"}}
            }}
          }}
        ]
      }},
      {"gridRenderer":{
        "header":{"gridHeaderRenderer":{"title":{"runs":[{"text":"Moods & genres"}]}}},
        "items":[
          {"musicNavigationButtonRenderer":{"buttonText":{"runs":[{"text":"Chill"}]}}}
        ]
      }}
    ]}}}}]}}}
    """

    @Test("Parses new-release carousels and skips card-less chip grids")
    func parsesCarouselsSkipsChips() throws {
        let response = try JSONDecoder().decode(BrowseResponse.self, from: Data(fixture.utf8))
        let shelves = ExploreParser.parse(response)

        // The mood/genre grid has no card renderers, so only the carousel survives.
        #expect(shelves.count == 1)
        let shelf = try #require(shelves.first)
        #expect(shelf.title == "New albums & singles")

        let album = try #require(shelf.items.first)
        #expect(album.kind == .album)
        #expect(album.title == "Some Album")
        #expect(album.browseId == "MPREb_xyz")
    }

    @Test("Parses the shelf header \"More\" button as a navigation action")
    func parsesShelfMoreButton() throws {
        let response = try JSONDecoder().decode(BrowseResponse.self, from: Data(fixture.utf8))
        let shelf = try #require(ExploreParser.parse(response).first)

        let button = try #require(shelf.buttons.first)
        #expect(button.title == "More")
        guard case .navigate(let destination) = button.action else {
            Issue.record("expected a navigate action, got \(button.action)")
            return
        }
        #expect(destination.browseId == "FEmusic_new_releases_albums")
        #expect(destination.kind == .playlist)
        // Titled with the shelf name so the destination reads sensibly while loading.
        #expect(destination.title == "New albums & singles")
    }

    @Test("A watch-endpoint header button parses as a play action")
    func parsesPlayAllButton() throws {
        let json = """
        {"contents":{"singleColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
          {"musicCarouselShelfRenderer":{
            "header":{"musicCarouselShelfBasicHeaderRenderer":{
              "title":{"runs":[{"text":"Quick picks"}]},
              "moreContentButton":{"buttonRenderer":{
                "text":{"runs":[{"text":"Play all"}]},
                "navigationEndpoint":{"watchEndpoint":{"videoId":"vid123","playlistId":"PL42"}}
              }}
            }},
            "contents":[
              {"musicResponsiveListItemRenderer":{
                "flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Some Song"}]}}}],
                "playlistItemData":{"videoId":"vid123"}
              }}
            ]
          }}
        ]}}}}]}}}
        """
        let response = try JSONDecoder().decode(BrowseResponse.self, from: Data(json.utf8))
        let shelf = try #require(ExploreParser.parse(response).first)

        let button = try #require(shelf.buttons.first)
        #expect(button.title == "Play all")
        #expect(button.action == .play(videoId: "vid123", playlistId: "PL42"))
    }

    @Test("An empty response yields no shelves")
    func emptyResponse() throws {
        let response = try JSONDecoder().decode(BrowseResponse.self, from: Data("{}".utf8))
        #expect(ExploreParser.parse(response).isEmpty)
    }
}
