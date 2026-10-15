//
//  PodcastTests.swift
//  YT MusicTests
//
//  Podcast show pages: the publisher byline, the saved state, and episode rows
//  (`musicMultiRowListItemRenderer`). Fixtures are trimmed from a live `browse`.
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Podcast show pages")
struct PodcastTests {
    private let destination = EntityDestination(
        browseId: "MPSPPLshow", kind: .podcast, title: "", subtitle: "", thumbnailURL: nil
    )

    private let fixture = """
    {"contents":{"twoColumnBrowseResultsRenderer":{
      "tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
        {"musicResponsiveHeaderRenderer":{
          "title":{"runs":[{"text":"The Show"}]},
          "straplineTextOne":{"runs":[{"text":"The Publisher","navigationEndpoint":{"browseEndpoint":{
            "browseId":"UCpub","browseEndpointContextSupportedConfigs":{"browseEndpointContextMusicConfig":{
              "pageType":"MUSIC_PAGE_TYPE_USER_CHANNEL"}}}}}]},
          "buttons":[{"toggleButtonRenderer":{"isToggled":true,
            "defaultServiceEndpoint":{"likeEndpoint":{"status":"LIKE","target":{"playlistId":"PLshow"}}}}}]
        }}
      ]}}}}],
      "secondaryContents":{"sectionListRenderer":{"contents":[{"musicShelfRenderer":{"contents":[
        {"musicMultiRowListItemRenderer":{
          "title":{"runs":[{"text":"Episode One"}]},
          "subtitle":{"runs":[{"text":"22K views"},{"text":" \\u2022 "},{"text":"Oct 1, 2021"}]},
          "onTap":{"watchEndpoint":{"videoId":"vid1"}},
          "playbackProgress":{"musicPlaybackProgressRenderer":{
            "durationText":{"runs":[{"text":" \\u2022 "},{"text":"5 min 58 sec"}]}}}
        }},
        {"musicMultiRowListItemRenderer":{
          "title":{"runs":[{"text":"Episode Two"}]},
          "onTap":{"watchEndpoint":{"videoId":"vid2"}}
        }}
      ]}}]}}
    }}}
    """

    private func parse() throws -> EntityPage {
        let response = try JSONDecoder().decode(EntityBrowseResponse.self, from: Data(fixture.utf8))
        return EntityPageParser.parse(response, fallback: destination)
    }

    @Test("A show header is a podcast with its publisher and saved state")
    func parsesHeader() throws {
        let header = try parse().header
        guard case .podcast = header.content else {
            Issue.record("expected a podcast header, got \(header.kind)")
            return
        }
        #expect(header.title == "The Show")
        #expect(header.isSaved == true)
        #expect(header.byline?.runs.first?.link?.browseId == "UCpub")
        #expect(header.collection == nil)
        #expect(header.artistPage == nil)
    }

    @Test("Episode rows become playable tracks with their date, views and duration")
    func parsesEpisodes() throws {
        let tracks = try parse().tracks
        #expect(tracks.map(\.videoId) == ["vid1", "vid2"])
        #expect(tracks.map(\.index) == [1, 2])
        #expect(tracks[0].title == "Episode One")
        #expect(tracks[0].subtitle == "22K views \u{2022} Oct 1, 2021")
        #expect(tracks[0].duration == "5 min 58 sec")
        #expect(tracks[1].duration == nil)
        #expect(tracks.map { $0.artists.map(\.browseId) } == [["UCpub"], ["UCpub"]])
    }

    @Test("A show's saveable playlist id is its browse id minus the MPSP prefix")
    func savablePlaylistId() {
        let model = EntityViewModel(destination: EntityDestination(
            browseId: "MPSPPLshow", kind: .podcast, title: "", subtitle: "", thumbnailURL: nil
        ))
        #expect(model.savablePlaylistId == "PLshow")
    }

    @Test("A podcast show's page type resolves to the podcast kind")
    func resolvesPodcastCards() throws {
        let json = """
        {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"The Show"}]},
          "navigationEndpoint":{"browseEndpoint":{"browseId":"MPSPPLshow","browseEndpointContextSupportedConfigs":{
            "browseEndpointContextMusicConfig":{"pageType":"MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE"}}}}}}
        """
        let item = try JSONDecoder().decode(CarouselItem.self, from: Data(json.utf8))
        let card = try #require(HomeFeedParser.makeItem(from: item))
        #expect(card.kind == .podcast)
        #expect(card.browseId == "MPSPPLshow")
    }

    private let chipsFixture = """
    {"contents":{"twoColumnBrowseResultsRenderer":{"secondaryContents":{"sectionListRenderer":{
      "header":{"chipCloudRenderer":{"chips":[
        {"chipCloudChipRenderer":{"text":{"runs":[{"text":"Latest"}]},"notSelectable":true,
          "navigationEndpoint":{"openPopupAction":{"popup":{"menuPopupRenderer":{"items":[
            {"menuNavigationItemRenderer":{"text":{"simpleText":"Latest"},"icon":{"iconType":"CHECK"},
              "navigationEndpoint":{"browseSectionListReloadEndpoint":{"continuation":{"reloadContinuationData":{"continuation":"LATEST"}}}}}},
            {"menuNavigationItemRenderer":{"text":{"simpleText":"Oldest"},
              "navigationEndpoint":{"browseSectionListReloadEndpoint":{"continuation":{"reloadContinuationData":{"continuation":"OLDEST"}}}}}}
          ]}}}}}},
        {"chipCloudChipRenderer":{"text":{"simpleText":"Unplayed"},"isSelected":false,
          "navigationEndpoint":{"browseSectionListReloadEndpoint":{"continuation":{"reloadContinuationData":{"continuation":"UNPLAYED"}}}}}}
      ]}},
      "contents":[]
    }}}}}
    """

    @Test("A show's chips: the sort menu becomes sort options and the rest filters")
    func parsesChips() throws {
        let response = try JSONDecoder().decode(EntityBrowseResponse.self, from: Data(chipsFixture.utf8))
        let page = EntityPageParser.parse(response, fallback: destination)
        #expect(page.filters == [PlaylistFilter(title: "Unplayed", token: "UNPLAYED")])
        #expect(page.sortOptions == [
            PlaylistSortOption(title: "Latest", action: .reload("LATEST"), isSelected: true),
            PlaylistSortOption(title: "Oldest", action: .reload("OLDEST")),
        ])
    }

    @Test("A show reload carries its episodes in a shelf continuation beside the chips")
    func parsesReload() throws {
        let reload = """
        {"continuationContents":{
          "sectionListContinuation":{"header":{"chipCloudRenderer":{"chips":[]}}},
          "musicShelfContinuation":{"contents":[
            {"musicMultiRowListItemRenderer":{"title":{"runs":[{"text":"Oldest Episode"}]},
              "onTap":{"watchEndpoint":{"videoId":"old1"}}}}
          ]}
        }}
        """
        let response = try JSONDecoder().decode(EntityBrowseResponse.self, from: Data(reload.utf8))
        let page = EntityPageParser.parseTrackReload(response, header: try parse().header)
        #expect(page.tracks.map(\.videoId) == ["old1"])
    }
}
