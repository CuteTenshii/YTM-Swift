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
