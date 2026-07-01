//
//  HistoryParserTests.swift
//  YT MusicTests
//
//  Tests for parsing the listening-history page (date-grouped track shelves).
//

import Testing
import Foundation
@testable import YT_Music

@Suite("History parser")
struct HistoryParserTests {

    private func response(from json: String) throws -> BrowseResponse {
        try JSONDecoder().decode(BrowseResponse.self, from: Data(json.utf8))
    }

    @Test("Parses date buckets into titled sections of tracks")
    func parsesSections() throws {
        let response = try response(from: """
        { "contents": { "singleColumnBrowseResultsRenderer": { "tabs": [ { "tabRenderer": {
          "content": { "sectionListRenderer": { "contents": [
            { "musicShelfRenderer": {
              "title": { "runs": [ { "text": "Today" } ] },
              "contents": [
                { "musicResponsiveListItemRenderer": {
                  "playlistItemData": { "videoId": "aaa111" },
                  "flexColumns": [
                    { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [ { "text": "First Song" } ] } } },
                    { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [ { "text": "An Artist" } ] } } }
                  ]
                } }
              ]
            } },
            { "musicShelfRenderer": {
              "title": { "runs": [ { "text": "Yesterday" } ] },
              "contents": [
                { "musicResponsiveListItemRenderer": {
                  "playlistItemData": { "videoId": "bbb222" },
                  "flexColumns": [
                    { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [ { "text": "Older Song" } ] } } }
                  ]
                } }
              ]
            } }
          ] } }
        } } ] } } }
        """)

        let sections = HistoryParser.parse(response)
        #expect(sections.count == 2)
        #expect(sections.first?.title == "Today")
        #expect(sections.last?.title == "Yesterday")

        let track = try #require(sections.first?.tracks.first)
        #expect(track.title == "First Song")
        #expect(track.videoId == "aaa111")
        #expect(track.index == 1)
    }

    @Test("Skips shelves with no playable tracks")
    func skipsEmpty() throws {
        let response = try response(from: """
        { "contents": { "singleColumnBrowseResultsRenderer": { "tabs": [ { "tabRenderer": {
          "content": { "sectionListRenderer": { "contents": [
            { "musicShelfRenderer": { "title": { "runs": [ { "text": "Today" } ] }, "contents": [] } }
          ] } }
        } } ] } } }
        """)
        #expect(HistoryParser.parse(response).isEmpty)
    }

    @Test("Extracts the per-row feedback token used to remove a history item")
    func parsesFeedbackToken() throws {
        let response = try response(from: """
        { "contents": { "singleColumnBrowseResultsRenderer": { "tabs": [ { "tabRenderer": {
          "content": { "sectionListRenderer": { "contents": [
            { "musicShelfRenderer": {
              "title": { "runs": [ { "text": "Today" } ] },
              "contents": [
                { "musicResponsiveListItemRenderer": {
                  "playlistItemData": { "videoId": "aaa111" },
                  "flexColumns": [
                    { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [ { "text": "Song" } ] } } }
                  ],
                  "menu": { "menuRenderer": { "items": [
                    { "menuNavigationItemRenderer": { "text": { "runs": [ { "text": "Play next" } ] } } },
                    { "menuServiceItemRenderer": { "serviceEndpoint": {
                      "feedbackEndpoint": { "feedbackToken": "FEEDBACK_TOKEN_XYZ" }
                    } } }
                  ] } }
                } }
              ]
            } }
          ] } }
        } } ] } } }
        """)

        let track = try #require(HistoryParser.parse(response).first?.tracks.first)
        #expect(track.feedbackToken == "FEEDBACK_TOKEN_XYZ")
    }
}
