//
//  PlaylistHeaderAndOrderTests.swift
//  YT MusicTests
//
//  Playlist owner bylines, the manual-ordering signal, and drag-to-reorder
//  moves, against fixtures shaped like live `browse` responses.
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Playlist header and ordering")
struct PlaylistHeaderAndOrderTests {
    private let destination = EntityDestination(
        browseId: "VLPLmine", kind: .playlist, title: "Card title", subtitle: "", thumbnailURL: nil
    )

    /// An owned playlist: its header is wrapped in the editable header, and its
    /// sort items edit the playlist ("Manual ordering" selected).
    private func ownedFixture(selectedOrder: Int) -> String {
        """
        {"contents":{"twoColumnBrowseResultsRenderer":{
          "tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
            {"musicEditablePlaylistDetailHeaderRenderer":{"header":{"musicResponsiveHeaderRenderer":{
              "title":{"runs":[{"text":"Fire"}]},
              "subtitle":{"runs":[{"text":"Playlist"},{"text":" • "},{"text":"Unlisted"},{"text":" • "},{"text":"2026"}]},
              "facepile":{"avatarStackViewModel":{
                "avatars":[{"avatarViewModel":{"image":{"sources":[{"url":"https://img/owner.jpg"}]}}}],
                "text":{"content":"Tenshii"},
                "rendererContext":{"commandContext":{"onTap":{"innertubeCommand":{"browseEndpoint":{
                  "browseId":"UCowner",
                  "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_USER_CHANNEL"}}
                }}}}}
              }}
            }},
            "editHeader":{"musicPlaylistEditHeaderRenderer":{"privacy":"UNLISTED"}}}}
          ]}}}}],
          "secondaryContents":{"sectionListRenderer":{"contents":[
            {"musicPlaylistShelfRenderer":{
              "header":{"musicSideAlignedItemRenderer":{"startItems":[{"sortFilterSubMenuRenderer":{"subMenuItems":[
                {"title":"Manual ordering","selected":\(selectedOrder == 0),"serviceEndpoint":{"playlistEditEndpoint":{
                  "actions":[{"action":"ACTION_SET_PLAYLIST_VIDEO_ORDER","playlistVideoOrder":0}]}}},
                {"title":"Newest first","selected":\(selectedOrder == 1),"serviceEndpoint":{"playlistEditEndpoint":{
                  "actions":[{"action":"ACTION_SET_PLAYLIST_VIDEO_ORDER","playlistVideoOrder":1}]}}}
              ]}}]}},
              "contents":[]
            }}
          ]}}
        }}}
        """
    }

    /// Someone else's playlist: owner without a link target, and sort items that
    /// reload rather than edit.
    private let otherFixture = """
    {"contents":{"twoColumnBrowseResultsRenderer":{
      "tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
        {"musicResponsiveHeaderRenderer":{
          "title":{"runs":[{"text":"Mix"}]},
          "facepile":{"avatarStackViewModel":{"text":{"content":"YouTube Music"}}}
        }}
      ]}}}}],
      "secondaryContents":{"sectionListRenderer":{"contents":[
        {"musicPlaylistShelfRenderer":{
          "header":{"musicSideAlignedItemRenderer":{"startItems":[{"sortFilterSubMenuRenderer":{"subMenuItems":[
            {"title":"Default ordering","selected":true,"navigationEndpoint":{"executeEntityCommand":{"commandEntityKey":"k"}}}
          ]}}]}},
          "contents":[]
        }}
      ]}}
    }}}
    """

    private func parse(_ json: String) throws -> EntityPage {
        let response = try JSONDecoder().decode(EntityBrowseResponse.self, from: Data(json.utf8))
        return EntityPageParser.parse(response, fallback: destination)
    }

    @Test("An owned playlist's editable header is parsed, with a linked owner byline")
    func ownedHeader() throws {
        let page = try parse(ownedFixture(selectedOrder: 0))
        #expect(page.header.title == "Fire")
        #expect(page.header.privacy == .unlisted)
        let byline = try #require(page.header.byline)
        #expect(byline.runs.map(\.text) == ["Tenshii"])
        #expect(byline.runs.first?.link?.browseId == "UCowner")
        #expect(byline.avatarURL?.absoluteString == "https://img/owner.jpg")
    }

    @Test("Manual ordering is detected only when selected")
    func manualOrdering() throws {
        #expect(try parse(ownedFixture(selectedOrder: 0)).isManuallyOrdered)
        #expect(try !parse(ownedFixture(selectedOrder: 1)).isManuallyOrdered)
        #expect(try !parse(otherFixture).isManuallyOrdered)
    }

    @Test("Playlists the user doesn't own have no visibility")
    func otherPrivacy() throws {
        #expect(try parse(otherFixture).header.privacy == nil)
    }

    @Test("An owner without a channel link is shown as plain text")
    func unlinkedOwner() throws {
        let byline = try #require(try parse(otherFixture).header.byline)
        #expect(byline.runs.map(\.text) == ["YouTube Music"])
        #expect(byline.runs.first?.link == nil)
        #expect(byline.avatarURL == nil)
    }

    @Test("A card is the user's own playlist only when its menu offers Edit playlist")
    func cardOwnership() throws {
        func card(menuItems: String) throws -> HomeItem? {
            let json = """
            {"title":{"runs":[{"text":"Fire"}]},
             "navigationEndpoint":{"browseEndpoint":{"browseId":"VLPLmine",
               "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_PLAYLIST"}}}},
             "menu":{"menuRenderer":{"items":[\(menuItems)]}}}
            """
            let row = try JSONDecoder().decode(MusicTwoRowItemRenderer.self, from: Data(json.utf8))
            return HomeFeedParser.makeItem(from: row)
        }
        let owned = try card(menuItems: """
            {"menuNavigationItemRenderer":{"navigationEndpoint":{"playlistEditorEndpoint":{"playlistId":"PLmine"}}}}
            """)
        #expect(owned?.editablePlaylistId == "PLmine")
        let saved = try card(menuItems: """
            {"menuNavigationItemRenderer":{"navigationEndpoint":{"shareEntityEndpoint":{}}}}
            """)
        #expect(saved?.editablePlaylistId == nil)
    }

    // MARK: - Moves

    private func tracks(_ ids: [String?]) -> [Track] {
        ids.enumerated().map { offset, id in
            var track = Track(index: offset + 1, title: id ?? "-", subtitle: "", duration: nil,
                              thumbnailURL: nil, videoId: "v\(offset)")
            track.playlistSetVideoId = id
            return track
        }
    }

    @Test("Moving down lands before the row at the drop offset")
    func moveDown() throws {
        let list = tracks(["a", "b", "c", "d"])
        let move = try #require(PlaylistMove(tracks: list, from: 0, toOffset: 3, hasMore: false))
        #expect(move.tracks.map(\.title) == ["b", "c", "a", "d"])
        #expect(move.tracks.map(\.index) == [1, 2, 3, 4])
        #expect(move.setVideoId == "a")
        #expect(move.successor == "d")
    }

    @Test("Moving up lands before the row at the drop offset")
    func moveUp() throws {
        let move = try #require(PlaylistMove(tracks: tracks(["a", "b", "c", "d"]), from: 3, toOffset: 1, hasMore: false))
        #expect(move.tracks.map(\.title) == ["a", "d", "b", "c"])
        #expect(move.successor == "b")
    }

    @Test("Moving past the last row of a fully loaded list moves to the end")
    func moveToEnd() throws {
        let move = try #require(PlaylistMove(tracks: tracks(["a", "b", "c"]), from: 0, toOffset: 3, hasMore: false))
        #expect(move.tracks.map(\.title) == ["b", "c", "a"])
        #expect(move.successor == nil)
    }

    @Test("Moves with no known successor, no change, or no setVideoId are rejected")
    func rejectedMoves() {
        let list = tracks(["a", "b", "c"])
        #expect(PlaylistMove(tracks: list, from: 0, toOffset: 3, hasMore: true) == nil)
        #expect(PlaylistMove(tracks: list, from: 1, toOffset: 1, hasMore: false) == nil)
        #expect(PlaylistMove(tracks: list, from: 1, toOffset: 2, hasMore: false) == nil)
        let gaps = tracks(["a", "b", nil, nil])
        #expect(PlaylistMove(tracks: gaps, from: 0, toOffset: 2, hasMore: false) == nil)
        #expect(PlaylistMove(tracks: gaps, from: 2, toOffset: 0, hasMore: false) == nil)
    }
}
