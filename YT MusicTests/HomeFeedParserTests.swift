//
//  HomeFeedParserTests.swift
//  YT MusicTests
//
//  Verifies parsing of the two-row song/video cards used by home & feed shelves
//  (no network): the channel byline that drives "Go to artist", and the like
//  state, which these cards carry in a menu *toggle* rather than a top-level
//  like button.
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Home feed parser")
struct HomeFeedParserTests {

    private func card(_ json: String) throws -> HomeItem {
        let item = try JSONDecoder().decode(CarouselItem.self, from: Data(json.utf8))
        return try #require(HomeFeedParser.makeItem(from: item))
    }

    @Test("A two-row card exposes its channel byline as a navigable artist")
    func channelBylineIsNavigable() throws {
        let home = try card("""
        {"musicTwoRowItemRenderer":{
          "title":{"runs":[{"text":"Some Song"}]},
          "subtitle":{"runs":[
            {"text":"Some Artist","navigationEndpoint":{"browseEndpoint":{"browseId":"UCchan",
              "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_USER_CHANNEL"}}}}},
            {"text":" • "},
            {"text":"Some Album","navigationEndpoint":{"browseEndpoint":{"browseId":"MPREbAlb",
              "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ALBUM"}}}}}
          ]},
          "navigationEndpoint":{"watchEndpoint":{"videoId":"vid1"}}
        }}
        """)

        #expect(home.artists.map(\.name) == ["Some Artist"])
        #expect(home.artists.first?.browseId == "UCchan")
        #expect(home.albumLink?.name == "Some Album")
    }

    @Test("A liked two-row card reads .liked from its like toggle")
    func likedToggleReadsLiked() throws {
        // The default (tap) action would set INDIFFERENT — so it's currently liked.
        let home = try card("""
        {"musicTwoRowItemRenderer":{
          "title":{"runs":[{"text":"S"}]},
          "navigationEndpoint":{"watchEndpoint":{"videoId":"v"}},
          "menu":{"menuRenderer":{"items":[
            {"toggleMenuServiceItemRenderer":{"defaultServiceEndpoint":{"likeEndpoint":{"status":"INDIFFERENT","target":{"videoId":"v"}}}}}
          ]}}
        }}
        """)
        #expect(home.likeStatus == .liked)
    }

    @Test("A not-liked two-row card reads .indifferent from its like toggle")
    func notLikedToggleReadsIndifferent() throws {
        // The default (tap) action would set LIKE — so it's currently not liked.
        let home = try card("""
        {"musicTwoRowItemRenderer":{
          "title":{"runs":[{"text":"S"}]},
          "navigationEndpoint":{"watchEndpoint":{"videoId":"v"}},
          "menu":{"menuRenderer":{"items":[
            {"toggleMenuServiceItemRenderer":{"defaultServiceEndpoint":{"likeEndpoint":{"status":"LIKE","target":{"videoId":"v"}}}}}
          ]}}
        }}
        """)
        #expect(home.likeStatus == .indifferent)
    }

    @Test("A playlist \"save to library\" toggle is not read as a like")
    func saveToggleIsNotALike() throws {
        // Same toggle shape, but it targets a playlistId — not a track rating.
        let home = try card("""
        {"musicTwoRowItemRenderer":{
          "title":{"runs":[{"text":"A Playlist"}]},
          "navigationEndpoint":{"browseEndpoint":{"browseId":"VLPL1",
            "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_PLAYLIST"}}}},
          "menu":{"menuRenderer":{"items":[
            {"toggleMenuServiceItemRenderer":{"defaultServiceEndpoint":{"likeEndpoint":{"status":"LIKE","target":{"playlistId":"PL1"}}}}}
          ]}}
        }}
        """)
        #expect(home.likeStatus == nil)   // no videoId-targeted like → unknown
    }

    @Test("Reads Home chips from the section-list header")
    func parsesHeaderChips() throws {
        let response = try JSONDecoder().decode(BrowseResponse.self, from: Data("""
        {"contents":{"singleColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{
          "sectionListRenderer":{
            "header":{"chipCloudRenderer":{"chips":[
              {"chipCloudChipRenderer":{"text":{"runs":[{"text":"Energize"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"FEmusic_home","params":"energize"}}}},
              {"chipCloudChipRenderer":{"text":{"runs":[{"text":"Relax"}]},"navigationEndpoint":{"browseEndpoint":{"browseId":"FEmusic_home","params":"relax"}}}}
            ]}},
            "contents":[]
          }
        }}}]}}}
        """.utf8))

        let feed = HomeFeedParser.parse(response)
        #expect(feed.chips.map(\.title) == ["Energize", "Relax"])
        #expect(feed.chips.map(\.params) == ["energize", "relax"])
    }
}
