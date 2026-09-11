//
//  EntityPageParserTests.swift
//  YT MusicTests
//
//  Verifies entity-page parsing against fixtures shaped like the real `browse`
//  response (no network). Focuses on the artist immersive header's subscribe
//  button, which drives the Subscribe/Subscribed toggle.
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Entity page parser")
struct EntityPageParserTests {

    private let artistDestination = EntityDestination(
        browseId: "UCabc",
        kind: .artist,
        title: "Some Artist",
        subtitle: "",
        thumbnailURL: nil
    )

    /// A trimmed artist immersive header carrying a subscribe button with both
    /// service endpoints and the current (subscribed) state.
    private let subscribedFixture = """
    {"header":{"musicImmersiveHeaderRenderer":{
      "title":{"runs":[{"text":"Some Artist"}]},
      "subscriptionButton":{"subscribeButtonRenderer":{
        "channelId":"UCabc",
        "subscribed":true,
        "serviceEndpoints":[
          {"subscribeEndpoint":{"channelIds":["UCabc"],"params":"SUB"}},
          {"unsubscribeEndpoint":{"channelIds":["UCabc"],"params":"UNSUB"}}
        ]
      }}
    }}}
    """

    @Test("Parses the artist subscribe button state and toggle params")
    func parsesSubscription() throws {
        let response = try JSONDecoder().decode(
            EntityBrowseResponse.self, from: Data(subscribedFixture.utf8)
        )
        let page = EntityPageParser.parse(response, fallback: artistDestination)

        let subscription = try #require(page.header.subscription)
        #expect(subscription.channelId == "UCabc")
        #expect(subscription.isSubscribed == true)
        #expect(subscription.subscribeParams == "SUB")
        #expect(subscription.unsubscribeParams == "UNSUB")
    }

    @Test("A header without a subscribe button yields no subscription")
    func noSubscriptionWhenAbsent() throws {
        let fixture = """
        {"header":{"musicImmersiveHeaderRenderer":{"title":{"runs":[{"text":"Some Artist"}]}}}}
        """
        let response = try JSONDecoder().decode(
            EntityBrowseResponse.self, from: Data(fixture.utf8)
        )
        let page = EntityPageParser.parse(response, fallback: artistDestination)
        #expect(page.header.subscription == nil)
    }

    /// A bare feed page — a shelf's "More" landing (e.g. "Listen again") — has no
    /// entity header and lays its cards out as a grid rather than a track list.
    private let feedFixture = """
    {"contents":{"singleColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
      {"gridRenderer":{"items":[
        {"musicTwoRowItemRenderer":{
          "title":{"runs":[{"text":"Some Song"}]},
          "subtitle":{"runs":[{"text":"Some Artist"}]},
          "navigationEndpoint":{"watchEndpoint":{"videoId":"vid1"}}
        }}
      ]}}
    ]}}}}]}}}
    """

    @Test("A channel's visual header yields avatar, subscribers, and a subscribe button")
    func parsesChannelVisualHeader() throws {
        let fixture = """
        {"header":{"musicVisualHeaderRenderer":{
          "title":{"runs":[{"text":"Camille Bonzon"}]},
          "foregroundThumbnail":{"musicThumbnailRenderer":{"thumbnail":{"thumbnails":[
            {"url":"https://example.com/avatar.jpg","width":120,"height":120}
          ]}}},
          "subscriptionButton":{"subscribeButtonRenderer":{
            "channelId":"UCchan","subscribed":false,
            "subscriberCountText":{"runs":[{"text":"79"}]},
            "serviceEndpoints":[
              {"subscribeEndpoint":{"channelIds":["UCchan"],"params":"SUB"}},
              {"unsubscribeEndpoint":{"channelIds":["UCchan"],"params":"UNSUB"}}
            ]
          }}
        }}}
        """
        let channelDestination = EntityDestination(
            browseId: "UCchan", kind: .artist, title: "Camille Bonzon", subtitle: "", thumbnailURL: nil
        )
        let response = try JSONDecoder().decode(EntityBrowseResponse.self, from: Data(fixture.utf8))
        let page = EntityPageParser.parse(response, fallback: channelDestination)

        #expect(page.header.title == "Camille Bonzon")
        #expect(page.header.subtitle == "79 subscribers")
        #expect(page.header.thumbnailURL?.absoluteString == "https://example.com/avatar.jpg")
        #expect(page.header.subscription?.channelId == "UCchan")
        #expect(page.header.subscription?.isSubscribed == false)
        #expect(page.header.subscription?.subscribeParams == "SUB")
    }

    @Test("A feed page parses its grid into a shelf and reads as a feed")
    func parsesFeedGridAsShelf() throws {
        let feedDestination = EntityDestination(
            browseId: "FEmusic_listen_again", kind: .unknown,
            title: "Listen again", subtitle: "", thumbnailURL: nil
        )
        let response = try JSONDecoder().decode(EntityBrowseResponse.self, from: Data(feedFixture.utf8))
        let page = EntityPageParser.parse(response, fallback: feedDestination)

        #expect(page.isFeed)
        #expect(page.tracks.isEmpty)
        let shelf = try #require(page.shelves.first)
        #expect(shelf.items.first?.title == "Some Song")
    }

    /// An uploaded album, shaped like the real `privately_owned_release_detail`
    /// response: the artist link is only in the header (with a
    /// `MUSIC_PAGE_TYPE_UNKNOWN` page type, its kind inferred from the browse id),
    /// and the track row carries no artist and no thumbnail — only the album link.
    private let uploadedAlbumFixture = """
    {
      "header":{"musicDetailHeaderRenderer":{
        "title":{"runs":[{"text":"Rendez-vous"}]},
        "subtitle":{"runs":[
          {"text":"Album"},{"text":" • "},
          {"text":"David Vendetta","navigationEndpoint":{"browseEndpoint":{
            "browseId":"FEmusic_library_privately_owned_artist_detaila_po_XYZ",
            "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_UNKNOWN"}}
          }}},
          {"text":" • "},{"text":"2007"}
        ]},
        "thumbnail":{"croppedSquareThumbnailRenderer":{"thumbnail":{"thumbnails":[
          {"url":"https://img/cover.jpg","width":544,"height":544}
        ]}}}
      }},
      "contents":{"singleColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
        {"musicShelfRenderer":{"contents":[
          {"musicResponsiveListItemRenderer":{
            "playlistItemData":{"videoId":"tYk0G1gzMg8"},
            "flexColumns":[
              {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Freaky Girl"}]}}},
              {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[]}}},
              {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[
                {"text":"Rendez-vous","navigationEndpoint":{"browseEndpoint":{
                  "browseId":"FEmusic_library_privately_owned_release_detailb_po_ABC",
                  "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ALBUM"}}
                }}}
              ]}}}
            ]
          }}
        ]}}
      ]}}}}]}}
    }
    """

    @Test("Uploaded album tracks inherit the artist and cover from the header")
    func uploadedAlbumInheritsArtistAndCover() throws {
        let response = try JSONDecoder().decode(
            EntityBrowseResponse.self, from: Data(uploadedAlbumFixture.utf8)
        )
        let albumDestination = EntityDestination(
            browseId: "FEmusic_library_privately_owned_release_detailb_po_ABC",
            kind: .album, title: "Rendez-vous", subtitle: "", thumbnailURL: nil
        )
        let page = EntityPageParser.parse(response, fallback: albumDestination)

        // The header artist link resolves despite the UNKNOWN page type.
        #expect(page.header.artists.first?.name == "David Vendetta")
        #expect(page.header.artists.first?.kind == .artist)

        let track = try #require(page.tracks.first)
        #expect(track.title == "Freaky Girl")
        #expect(track.videoId == "tYk0G1gzMg8")
        // Artist inherited from the header — not the album name.
        #expect(track.subtitle == "David Vendetta")
        #expect(track.artists.first?.name == "David Vendetta")
        // Cover falls back to the album artwork instead of a blank placeholder.
        #expect(track.thumbnailURL?.absoluteString == "https://img/cover.jpg")
        // The row's album link is still captured.
        #expect(track.albumLink?.name == "Rendez-vous")
    }

    /// A real (non-uploaded) album in the newer two-column layout: there is no
    /// top-level `header`; the `musicResponsiveHeaderRenderer` lives inside the
    /// primary tab's section list, and the tracks (with a "plays" byline, no
    /// per-row artist, no per-row artwork) come from `secondaryContents`.
    private let twoColumnAlbumFixture = """
    {
      "contents":{"twoColumnBrowseResultsRenderer":{
        "tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
          {"musicResponsiveHeaderRenderer":{
            "title":{"runs":[{"text":"MG Ultra"}]},
            "straplineTextOne":{"runs":[
              {"text":"Some Artist","navigationEndpoint":{"browseEndpoint":{
                "browseId":"UCartist",
                "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ARTIST"}}
              }}}
            ]},
            "subtitle":{"runs":[{"text":"Album"},{"text":" • "},{"text":"2024"}]},
            "secondSubtitle":{"runs":[{"text":"12 songs • 45 minutes"}]},
            "thumbnail":{"musicThumbnailRenderer":{"thumbnail":{"thumbnails":[
              {"url":"https://img/mgultra.jpg","width":544,"height":544}
            ]}}}
          }}
        ]}}}}],
        "secondaryContents":{"sectionListRenderer":{"contents":[
          {"musicShelfRenderer":{"contents":[
            {"musicResponsiveListItemRenderer":{
              "playlistItemData":{"videoId":"vid1"},
              "flexColumns":[
                {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Until I Die"}]}}},
                {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"1.3M plays"}]}}}
              ],
              "menu":{"menuRenderer":{"topLevelButtons":[
                {"likeButtonRenderer":{"likeStatus":"LIKE","target":{"videoId":"vid1"}}}
              ]}}
            }}
          ]}}
        ]}}
      }}
    }
    """

    @Test("A two-column album parses its nested header (cover, subtitle, artist)")
    func twoColumnAlbumParsesNestedHeader() throws {
        let response = try JSONDecoder().decode(
            EntityBrowseResponse.self, from: Data(twoColumnAlbumFixture.utf8)
        )
        let albumDestination = EntityDestination(
            browseId: "MPREb_mgultra", kind: .album,
            title: "MG Ultra", subtitle: "", thumbnailURL: nil
        )
        let page = EntityPageParser.parse(response, fallback: albumDestination)

        // Header details recovered from the body's responsive header.
        #expect(page.header.title == "MG Ultra")
        #expect(page.header.subtitle.contains("2024"))
        #expect(page.header.thumbnailURL?.absoluteString == "https://img/mgultra.jpg")
        #expect(page.header.artists.first?.name == "Some Artist")

        let track = try #require(page.tracks.first)
        #expect(track.title == "Until I Die")
        #expect(track.videoId == "vid1")
        // The row's "plays" byline is kept (not overwritten by the artist name)…
        #expect(track.subtitle == "1.3M plays")
        // …but the artist link is still adopted from the header for context menus.
        #expect(track.artists.first?.name == "Some Artist")
        // Track artwork falls back to the album cover.
        #expect(track.thumbnailURL?.absoluteString == "https://img/mgultra.jpg")
        // The current like rating is read straight from the row's menu.
        #expect(track.likeStatus == .liked)
    }

    @Test("Playlist shelves preserve and parse continuation pages")
    func parsesPlaylistContinuations() throws {
        let initialFixture = """
        {
          "contents":{"singleColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
            {"musicPlaylistShelfRenderer":{
              "contents":[{"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"vid1"},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"First song"}]}}}]}}],
              "continuations":[{"nextContinuationData":{"continuation":"PAGE_2"}}]
            }}
          ]}}}}]}}
        }
        """
        let destination = EntityDestination(
            browseId: "VLPL123", kind: .playlist, title: "Playlist", subtitle: "", thumbnailURL: nil
        )
        let initial = try JSONDecoder().decode(
            EntityBrowseResponse.self, from: Data(initialFixture.utf8)
        )
        let page = EntityPageParser.parse(initial, fallback: destination)

        #expect(page.tracks.count == 1)
        #expect(page.continuationToken == "PAGE_2")

        let continuationFixture = """
        {"continuationContents":{"musicPlaylistShelfContinuation":{
          "contents":[{"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"vid2"},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Second song"}]}}}]}}],
          "continuations":[]
        }}}
        """
        let continuation = try JSONDecoder().decode(
            EntityBrowseResponse.self, from: Data(continuationFixture.utf8)
        )
        let next = EntityPageParser.parseContinuation(
            continuation, startIndex: page.tracks.count + 1, header: page.header
        )

        #expect(next.tracks.first?.title == "Second song")
        #expect(next.tracks.first?.index == 2)
        #expect(next.continuationToken == nil)
    }

    @Test("Playlist section continuations are preserved")
    func parsesSectionContinuation() throws {
        let fixture = """
        {
          "contents":{"singleColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{
            "contents":[{"musicPlaylistShelfRenderer":{"contents":[]}}],
            "continuations":[{"nextContinuationData":{"continuation":"SECTION_PAGE_2"}}]
          }}}}]}}
        }
        """
        let response = try JSONDecoder().decode(
            EntityBrowseResponse.self, from: Data(fixture.utf8)
        )
        let destination = EntityDestination(
            browseId: "VLPL123", kind: .playlist, title: "Playlist", subtitle: "", thumbnailURL: nil
        )
        let page = EntityPageParser.parse(response, fallback: destination)

        #expect(page.continuationToken == "SECTION_PAGE_2")
    }
}

@Suite("Playlist save target")
@MainActor
struct PlaylistSaveTests {

    private func model(browseId: String, kind: HomeItem.Kind) -> EntityViewModel {
        EntityViewModel(destination: EntityDestination(
            browseId: browseId, kind: kind, title: "", subtitle: "", thumbnailURL: nil
        ))
    }

    @Test("A playlist's save target strips the VL browse-id prefix")
    func derivesPlaylistIdFromVLPrefix() {
        #expect(model(browseId: "VLPL123", kind: .playlist).savablePlaylistId == "PL123")
    }

    @Test("A bare playlist id (no VL prefix) is used as-is")
    func usesBarePlaylistId() {
        #expect(model(browseId: "PL123", kind: .playlist).savablePlaylistId == "PL123")
    }

    @Test("Albums and artists are not savable this way")
    func onlyPlaylistsAreSavable() {
        #expect(model(browseId: "MPREb_abc", kind: .album).savablePlaylistId == nil)
        #expect(model(browseId: "UCabc", kind: .artist).savablePlaylistId == nil)
    }
}
