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

    @Test("Parses the artist header's Shuffle and Start radio mix ids separately")
    func parsesArtistMixIds() throws {
        let fixture = """
        {"header":{"musicImmersiveHeaderRenderer":{
          "title":{"runs":[{"text":"Some Artist"}]},
          "playButton":{"buttonRenderer":{"navigationEndpoint":{"watchPlaylistEndpoint":{"playlistId":"RDAOshuffle"}}}},
          "startRadioButton":{"buttonRenderer":{"navigationEndpoint":{"watchPlaylistEndpoint":{"playlistId":"RDEMradio"}}}}
        }}}
        """
        let response = try JSONDecoder().decode(
            EntityBrowseResponse.self, from: Data(fixture.utf8)
        )
        let page = EntityPageParser.parse(response, fallback: artistDestination)
        #expect(page.header.radioPlaylistId == "RDAOshuffle")
        #expect(page.header.startRadioPlaylistId == "RDEMradio")
    }

    @Test("Reads the page's canonical share URL from its microformat")
    func parsesShareURL() throws {
        let fixture = """
        {"microformat":{"microformatDataRenderer":{
          "urlCanonical":"https://music.youtube.com/playlist?list=OLAK5uy_album"}}}
        """
        let response = try JSONDecoder().decode(
            EntityBrowseResponse.self, from: Data(fixture.utf8)
        )
        let page = EntityPageParser.parse(response, fallback: artistDestination)
        #expect(page.shareURL?.absoluteString == "https://music.youtube.com/playlist?list=OLAK5uy_album")
    }

    private let playlistDestination = EntityDestination(
        browseId: "VLLM", kind: .playlist, title: "Liked Music", subtitle: "", thumbnailURL: nil
    )

    @Test("Parses a playlist's filter chips with their reload and clear tokens")
    func parsesPlaylistFilters() throws {
        let fixture = """
        {"contents":{"twoColumnBrowseResultsRenderer":{"secondaryContents":{"sectionListRenderer":{
          "header":{"chipCloudRenderer":{"chips":[
            {"chipCloudChipRenderer":{
              "text":{"runs":[{"text":"Party"}]},
              "navigationEndpoint":{"browseSectionListReloadEndpoint":{"continuation":{"reloadContinuationData":{"continuation":"PARTY"}}}},
              "onDeselectedCommand":{"browseSectionListReloadEndpoint":{"continuation":{"reloadContinuationData":{"continuation":"ALL"}}}}
            }}
          ]}},
          "contents":[]
        }}}}}
        """
        let response = try JSONDecoder().decode(EntityBrowseResponse.self, from: Data(fixture.utf8))
        let page = EntityPageParser.parse(response, fallback: playlistDestination)
        #expect(page.filters == [PlaylistFilter(title: "Party", token: "PARTY", clearToken: "ALL")])
    }

    @Test("Parses a track reload: tracks, next token, and the new filter and sort selection")
    func parsesTrackReload() throws {
        let fixture = """
        {"continuationContents":{"sectionListContinuation":{
          "header":{"chipCloudRenderer":{"chips":[
            {"chipCloudChipRenderer":{
              "text":{"runs":[{"text":"Party"}]}, "isSelected":true,
              "navigationEndpoint":{"browseSectionListReloadEndpoint":{"continuation":{"reloadContinuationData":{"continuation":"PARTY"}}}}
            }}
          ]}},
          "contents":[
          {"musicPlaylistShelfRenderer":{
            "header":{"musicSideAlignedItemRenderer":{"startItems":[{"sortFilterSubMenuRenderer":{"subMenuItems":[
              {"title":"Newest first","selected":true,"navigationEndpoint":{"executeEntityCommand":{"commandEntityKey":"K1"}}},
              {"title":"Title","selected":false,"navigationEndpoint":{"executeEntityCommand":{"commandEntityKey":"K2"}}}
            ]}}]}},
            "contents":[
            {"musicResponsiveListItemRenderer":{
              "flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Some Song"}]}}}],
              "playlistItemData":{"videoId":"vid1"}
            }},
            {"continuationItemRenderer":{"continuationEndpoint":{"continuationCommand":{"token":"NEXT"}}}}
          ]}}
        ]}},
        "frameworkUpdates":{"entityBatchUpdate":{"mutations":[
          {"entityKey":"K1","payload":{"commandEntity":{"command":{"browseSectionListReloadEndpoint":{"continuation":{"reloadContinuationData":{"continuation":"NEWEST"}}}}}}},
          {"entityKey":"K2","payload":{"commandEntity":{"command":{"browseSectionListReloadEndpoint":{"continuation":{"reloadContinuationData":{"continuation":"TITLE"}}}}}}}
        ]}}}
        """
        let response = try JSONDecoder().decode(EntityBrowseResponse.self, from: Data(fixture.utf8))
        let header = EntityHeader(title: "", subtitle: "", description: "", thumbnailURL: nil, kind: .playlist)
        let reload = EntityPageParser.parseTrackReload(response, header: header)
        #expect(reload.tracks.map(\.videoId) == ["vid1"])
        #expect(reload.tracks.map(\.index) == [1])
        #expect(reload.continuationToken == "NEXT")
        #expect(reload.filters.map(\.isSelected) == [true])
        #expect(reload.sortOptions == [
            PlaylistSortOption(title: "Newest first", action: .reload("NEWEST"), isSelected: true),
            PlaylistSortOption(title: "Title", action: .reload("TITLE")),
        ])
    }

    private func headerFixture(saved: Bool) -> String {
        """
        {"contents":{"twoColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
          {"musicResponsiveHeaderRenderer":{
            "title":{"runs":[{"text":"Some Playlist"}]},
            "buttons":[
              {"toggleButtonRenderer":{
                "isToggled":\(saved),
                "defaultServiceEndpoint":{"likeEndpoint":{"status":"LIKE","target":{"playlistId":"PLabc"}}}
              }}
            ]
          }}
        ]}}}}]}}}
        """
    }

    @Test("Reads a playlist's saved state from its Save to library toggle", arguments: [true, false])
    func parsesSavedState(saved: Bool) throws {
        let response = try JSONDecoder().decode(
            EntityBrowseResponse.self, from: Data(headerFixture(saved: saved).utf8)
        )
        let page = EntityPageParser.parse(response, fallback: playlistDestination)
        #expect(page.header.isSaved == saved)
    }

    @Test("A header without the save toggle leaves the saved state unknown")
    func savedStateUnknownWithoutToggle() throws {
        let fixture = """
        {"contents":{"twoColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
          {"musicResponsiveHeaderRenderer":{"title":{"runs":[{"text":"My Playlist"}]}}}
        ]}}}}]}}}
        """
        let response = try JSONDecoder().decode(EntityBrowseResponse.self, from: Data(fixture.utf8))
        #expect(EntityPageParser.parse(response, fallback: playlistDestination).header.isSaved == nil)
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
        #expect(page.header.subscription?.isEnabled == true)
    }

    @Test("The user's own channel has its subscribe button disabled")
    func ownChannelSubscriptionDisabled() throws {
        let fixture = """
        {"header":{"musicVisualHeaderRenderer":{
          "title":{"runs":[{"text":"Me"}]},
          "subscriptionButton":{"subscribeButtonRenderer":{
            "channelId":"UCme","subscribed":false,"enabled":false
          }}
        }}}
        """
        let destination = EntityDestination(browseId: "UCme", kind: .artist, title: "Me", subtitle: "", thumbnailURL: nil)
        let response = try JSONDecoder().decode(EntityBrowseResponse.self, from: Data(fixture.utf8))
        let page = EntityPageParser.parse(response, fallback: destination)
        #expect(page.header.subscription?.isEnabled == false)
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

    @Test("An uploaded track with no artist tag doesn't show the album name as its artist")
    func uploadedTrackWithoutArtist() throws {
        let fixture = """
        {
          "header":{"musicDetailHeaderRenderer":{
            "title":{"runs":[{"text":"Album Name"}]},
            "subtitle":{"runs":[{"text":"Album"},{"text":" • "},{"text":"2014"}]}
          }},
          "contents":{"singleColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
            {"musicShelfRenderer":{"contents":[
              {"musicResponsiveListItemRenderer":{
                "playlistItemData":{"videoId":"vid1"},
                "flexColumns":[
                  {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Some Artist - Song Name"}]}}},
                  {"musicResponsiveListItemFlexColumnRenderer":{"text":{}}},
                  {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[
                    {"text":"Album Name","navigationEndpoint":{"browseEndpoint":{
                      "browseId":"FEmusic_library_privately_owned_release_detailb_po_DUMMY",
                      "browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_ALBUM"}}
                    }}}
                  ]}}}
                ]
              }}
            ]}}
          ]}}}}]}}
        }
        """
        let response = try JSONDecoder().decode(EntityBrowseResponse.self, from: Data(fixture.utf8))
        let albumDestination = EntityDestination(
            browseId: "FEmusic_library_privately_owned_release_detailb_po_DUMMY",
            kind: .album, title: "Album Name", subtitle: "", thumbnailURL: nil
        )
        let track = try #require(EntityPageParser.parse(response, fallback: albumDestination).tracks.first)
        #expect(track.title == "Some Artist - Song Name")
        #expect(track.subtitle.isEmpty)
        #expect(track.albumLink?.name == "Album Name")
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
            "straplineThumbnail":{"musicThumbnailRenderer":{"thumbnail":{"thumbnails":[
              {"url":"https://img/artist.jpg","width":60,"height":60}
            ]}}},
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
        // The artist is shown as a linked byline, not repeated in the subtitle.
        #expect(page.header.byline?.runs.first?.link?.browseId == "UCartist")
        #expect(page.header.byline?.avatarURL?.absoluteString == "https://img/artist.jpg")
        #expect(!page.header.subtitle.contains("Some Artist"))

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

    @Test("A remove-from-playlist menu action — not a bare setVideoId — marks a row removable")
    func playlistRemovalPermissionComesFromTheRowMenu() throws {
        let fixture = """
        {
          "contents":{"singleColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
            {"musicPlaylistShelfRenderer":{"contents":[
              {"musicResponsiveListItemRenderer":{
                "playlistItemData":{"videoId":"vid1","playlistSetVideoId":"set1"},
                "flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Owned row"}]}}}],
                "menu":{"menuRenderer":{"items":[
                  {"menuServiceItemRenderer":{"serviceEndpoint":{
                    "playlistEditEndpoint":{"playlistId":"PL123","actions":[{"action":"ACTION_REMOVE_VIDEO","removedVideoId":"vid1"}]}
                  }}}
                ]}}
              }},
              {"musicResponsiveListItemRenderer":{
                "playlistItemData":{"videoId":"vid2","playlistSetVideoId":"set2"},
                "flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Saved-playlist row"}]}}}]
              }}
            ]}}
          ]}}}}]}}
        }
        """
        let response = try JSONDecoder().decode(
            EntityBrowseResponse.self, from: Data(fixture.utf8)
        )
        let destination = EntityDestination(
            browseId: "VLPL123", kind: .playlist, title: "Playlist", subtitle: "", thumbnailURL: nil
        )
        let page = EntityPageParser.parse(response, fallback: destination)

        // Both rows carry the removal plumbing (setVideoId)…
        #expect(page.tracks.allSatisfy { $0.playlistSetVideoId != nil })
        // …but only the one whose menu offers the remove action is removable:
        #expect(page.tracks[0].canRemoveFromPlaylist == true)
        #expect(page.tracks[1].canRemoveFromPlaylist == false)
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
