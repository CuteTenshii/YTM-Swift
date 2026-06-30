//
//  SearchParserTests.swift
//  YT MusicTests
//
//  Verifies search-result parsing against a fixture shaped like the real
//  `search` response (no network): category shelves with song and album rows.
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Search parser")
struct SearchParserTests {

    /// A trimmed two-tab-free search response: a "Songs" shelf with one playable
    /// row (watch endpoint via the play-button overlay) and an "Albums" shelf
    /// with one browsable row.
    private let fixture = """
    {"contents":{"tabbedSearchResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
      {"musicShelfRenderer":{
        "title":{"runs":[{"text":"Songs"}]},
        "contents":[
          {"musicResponsiveListItemRenderer":{
            "flexColumns":[
              {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Bohemian Rhapsody"}]}}},
              {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Queen"}]}}}
            ],
            "fixedColumns":[
              {"musicResponsiveListItemFixedColumnRenderer":{"text":{"runs":[{"text":"5:55"}]}}}
            ],
            "overlay":{"musicItemThumbnailOverlayRenderer":{"content":{"musicPlayButtonRenderer":{
              "playNavigationEndpoint":{"watchEndpoint":{"videoId":"fJ9rUzIMcZQ"}}
            }}}}
          }}
        ]
      }},
      {"musicShelfRenderer":{
        "title":{"runs":[{"text":"Albums"}]},
        "contents":[
          {"musicResponsiveListItemRenderer":{
            "flexColumns":[
              {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"A Night at the Opera"}]}}},
              {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Queen"}]}}}
            ],
            "navigationEndpoint":{"browseEndpoint":{
              "browseId":"MPREb_album",
              "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ALBUM"}}
            }}
          }}
        ]
      }}
    ]}}}}]}}}
    """

    @Test("Groups results into category shelves with the right kinds")
    func parsesCategories() throws {
        let response = try JSONDecoder().decode(SearchResponse.self, from: Data(fixture.utf8))
        let shelves = SearchParser.parse(response)

        #expect(shelves.count == 2)

        let songs = try #require(shelves.first { $0.title == "Songs" })
        let song = try #require(songs.items.first)
        #expect(song.kind == .song)
        #expect(song.title == "Bohemian Rhapsody")
        #expect(song.subtitle == "Queen")
        #expect(song.videoId == "fJ9rUzIMcZQ")
        #expect(song.entityDestination == nil)   // songs play, they don't navigate

        let albums = try #require(shelves.first { $0.title == "Albums" })
        let album = try #require(albums.items.first)
        #expect(album.kind == .album)
        #expect(album.title == "A Night at the Opera")
        #expect(album.browseId == "MPREb_album")
        #expect(album.entityDestination != nil)
    }

    @Test("An empty response yields no shelves")
    func emptyResponse() throws {
        let response = try JSONDecoder().decode(SearchResponse.self, from: Data("{}".utf8))
        #expect(SearchParser.parse(response).isEmpty)
    }

    /// The real default ("everything") search layout: a top-result card followed
    /// by ungrouped rows, each wrapped in its own `itemSectionRenderer`.
    private let flatFixture = """
    {"contents":{"tabbedSearchResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
      {"itemSectionRenderer":{"contents":[{"messageRenderer":{"text":{"runs":[{"text":""}]}}}]}},
      {"musicCardShelfRenderer":{
        "title":{"runs":[{"text":"Queen","navigationEndpoint":{"browseEndpoint":{
          "browseId":"UCqueen",
          "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ARTIST"}}
        }}}]},
        "subtitle":{"runs":[{"text":"Artist • 140M monthly audience"}]},
        "onTap":{"browseEndpoint":{
          "browseId":"UCqueen",
          "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ARTIST"}}
        }}
      }},
      {"itemSectionRenderer":{"contents":[{"musicResponsiveListItemRenderer":{
        "flexColumns":[
          {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Greatest Hits"}]}}},
          {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Album • Queen • 1981"}]}}}
        ],
        "navigationEndpoint":{"browseEndpoint":{
          "browseId":"MPREb_hits",
          "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ALBUM"}}
        }}
      }}]}},
      {"itemSectionRenderer":{"contents":[{"musicResponsiveListItemRenderer":{
        "flexColumns":[
          {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Another One Bites The Dust"}]}}},
          {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Song • Queen"}]}}}
        ],
        "playlistItemData":{"videoId":"bdf_ll68Z8o"},
        "overlay":{"musicItemThumbnailOverlayRenderer":{"content":{"musicPlayButtonRenderer":{
          "playNavigationEndpoint":{"watchEndpoint":{"videoId":"bdf_ll68Z8o","watchEndpointMusicSupportedConfigs":{"watchEndpointMusicConfig":{"musicVideoType":"MUSIC_VIDEO_TYPE_ATV"}}}}
        }}}}
      }}]}},
      {"itemSectionRenderer":{"contents":[{"musicResponsiveListItemRenderer":{
        "flexColumns":[
          {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Bohemian Rhapsody (Official Video)"}]}}},
          {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Video • Queen"}]}}}
        ],
        "overlay":{"musicItemThumbnailOverlayRenderer":{"content":{"musicPlayButtonRenderer":{
          "playNavigationEndpoint":{"watchEndpoint":{"videoId":"vid_omv","watchEndpointMusicSupportedConfigs":{"watchEndpointMusicConfig":{"musicVideoType":"MUSIC_VIDEO_TYPE_OMV"}}}}
        }}}}
      }}]}},
      {"itemSectionRenderer":{"contents":[{"musicResponsiveListItemRenderer":{
        "flexColumns":[
          {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Some Episode"}]}}},
          {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Episode • Some Show"}]}}}
        ],
        "overlay":{"musicItemThumbnailOverlayRenderer":{"content":{"musicPlayButtonRenderer":{
          "playNavigationEndpoint":{"watchEndpoint":{"videoId":"ep_id","watchEndpointMusicSupportedConfigs":{"watchEndpointMusicConfig":{"musicVideoType":"MUSIC_VIDEO_TYPE_PODCAST_EPISODE"}}}}
        }}}}
      }}]}},
      {"itemSectionRenderer":{"contents":[{"musicResponsiveListItemRenderer":{
        "flexColumns":[
          {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"QueenFan99"}]}}},
          {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Profile • 1K subscribers"}]}}}
        ],
        "navigationEndpoint":{"browseEndpoint":{
          "browseId":"UCprofile",
          "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_USER_CHANNEL"}}
        }}
      }}]}},
      {"itemSectionRenderer":{"contents":[{"musicResponsiveListItemRenderer":{
        "flexColumns":[
          {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"The Queen Podcast"}]}}},
          {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Podcast • Host"}]}}}
        ],
        "navigationEndpoint":{"browseEndpoint":{
          "browseId":"MPSPpodcast",
          "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE"}}
        }}
      }}]}}
    ]}}}}]}}}
    """

    @Test("Flat results are grouped into ordered category shelves")
    func parsesFlatLayout() throws {
        let response = try JSONDecoder().decode(SearchResponse.self, from: Data(flatFixture.utf8))
        let shelves = SearchParser.parse(response)

        // Top result first, then categories in SearchCategory.allCases order.
        #expect(shelves.map(\.title) == [
            "Top result", "Songs", "Videos", "Albums", "Podcasts", "Episodes", "Profiles",
        ])

        let top = try #require(shelves.first { $0.title == "Top result" })
        #expect(top.items.first?.kind == .artist)
        #expect(top.items.first?.browseId == "UCqueen")

        let song = try #require(shelves.first { $0.title == "Songs" }?.items.first)
        #expect(song.videoId == "bdf_ll68Z8o")

        let video = try #require(shelves.first { $0.title == "Videos" }?.items.first)
        #expect(video.videoId == "vid_omv")

        #expect(shelves.first { $0.title == "Albums" }?.items.first?.browseId == "MPREb_hits")
        #expect(shelves.first { $0.title == "Episodes" }?.items.first?.videoId == "ep_id")
        #expect(shelves.first { $0.title == "Profiles" }?.items.first?.browseId == "UCprofile")
        #expect(shelves.first { $0.title == "Podcasts" }?.items.first?.browseId == "MPSPpodcast")
    }
}

@Suite("Search filters")
struct SearchFilterTests {

    @Test("the All filter sends no params; the rest each carry one")
    func paramsPresence() {
        #expect(SearchFilter.all.params == nil)
        for filter in SearchFilter.allCases where filter != .all {
            #expect(filter.params?.isEmpty == false)
        }
    }

    @Test("each scoped filter maps to a distinct params value")
    func paramsAreDistinct() {
        let scoped = SearchFilter.allCases.compactMap(\.params)
        #expect(Set(scoped).count == scoped.count)
    }
}
