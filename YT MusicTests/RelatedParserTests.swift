//
//  RelatedParserTests.swift
//  YT MusicTests
//
//  Verifies the watch-next "Related" browse decode + parse, against a fixture
//  shaped like the real response (shelves directly under a section list, no tab
//  wrapper).
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Related parser")
struct RelatedParserTests {

    // A song carousel and an album carousel, the way the related page nests them.
    private let fixture = """
    {"contents":{"sectionListRenderer":{"contents":[
    {"musicCarouselShelfRenderer":{
      "header":{"musicCarouselShelfBasicHeaderRenderer":{"title":{"runs":[{"text":"You might also like"}]}}},
      "contents":[
        {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"A Song"}]},
         "subtitle":{"runs":[{"text":"Some Artist"}]},
         "navigationEndpoint":{"watchEndpoint":{"videoId":"vid123"}}}},
        {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"An Album"}]},
         "subtitle":{"runs":[{"text":"Some Artist"}]},
         "navigationEndpoint":{"browseEndpoint":{"browseId":"MPREb_x",
           "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":
             {"pageType":"MUSIC_PAGE_TYPE_ALBUM"}}}}}}
      ]}},
    {"musicDescriptionShelfRenderer":{"description":{"runs":[{"text":"About this song…"}]}}}
    ]}}}
    """

    @Test("Parses carousel shelves, resolving song vs. album items")
    func parsesShelves() throws {
        let response = try JSONDecoder().decode(BrowseResponse.self, from: Data(fixture.utf8))
        let shelves = RelatedParser.parse(response)

        #expect(shelves.count == 1)   // the description shelf carries no cards → skipped
        let shelf = try #require(shelves.first)
        #expect(shelf.title == "You might also like")
        #expect(shelf.items.count == 2)

        #expect(shelf.items[0].title == "A Song")
        #expect(shelf.items[0].kind == .song)
        #expect(shelf.items[0].videoId == "vid123")
        #expect(shelf.items[0].entityDestination == nil)   // songs play, not navigate

        #expect(shelf.items[1].title == "An Album")
        #expect(shelf.items[1].kind == .album)
        #expect(shelf.items[1].browseId == "MPREb_x")
        #expect(shelf.items[1].entityDestination != nil)   // albums navigate
    }

    @Test("A grid carousel keeps its rows per column")
    func gridShelf() throws {
        let json = """
        {"contents":{"sectionListRenderer":{"contents":[
        {"musicCarouselShelfRenderer":{
          "header":{"musicCarouselShelfBasicHeaderRenderer":{"title":{"runs":[{"text":"You might also like"}]}}},
          "numItemsPerColumn":"4",
          "contents":[{"musicResponsiveListItemRenderer":{
            "flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"A Song"}]}}}],
            "playlistItemData":{"videoId":"vid123"}
          }}]}}
        ]}}}
        """
        let response = try JSONDecoder().decode(BrowseResponse.self, from: Data(json.utf8))
        let shelf = try #require(RelatedParser.parse(response).first)
        #expect(shelf.gridRows == 4)
    }

    @Test("An unrecognized response yields no shelves")
    func emptyOnGarbage() throws {
        let response = try JSONDecoder().decode(BrowseResponse.self, from: Data("{}".utf8))
        #expect(RelatedParser.parse(response).isEmpty)
    }
}
