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
