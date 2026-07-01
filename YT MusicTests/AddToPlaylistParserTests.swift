//
//  AddToPlaylistParserTests.swift
//  YT MusicTests
//
//  Tests parsing the `playlist/get_add_to_playlist` response — the editable
//  playlists YT Music offers when adding a track — into `EditablePlaylist`s.
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Add-to-playlist parser")
struct AddToPlaylistParserTests {

    private func response(from json: String) throws -> AddToPlaylistResponse {
        try JSONDecoder().decode(AddToPlaylistResponse.self, from: Data(json.utf8))
    }

    @Test("Maps playlist options (runs or simpleText titles) to editable playlists")
    func parsesOptions() throws {
        let response = try response(from: """
        { "contents": { "addToPlaylistRenderer": { "playlists": [
          { "playlistAddToOptionRenderer": {
            "playlistId": "PLaaa",
            "title": { "runs": [ { "text": "Road Trip" } ] }
          } },
          { "playlistAddToOptionRenderer": {
            "playlistId": "PLbbb",
            "title": { "simpleText": "Focus" },
            "thumbnail": { "thumbnails": [ { "url": "https://img/x", "width": 60 } ] }
          } },
          { "playlistAddToOptionRenderer": { "title": { "simpleText": "No id, dropped" } } }
        ] } } }
        """)

        let playlists = AddToPlaylistParser.parse(response)
        #expect(playlists.count == 2)
        #expect(playlists.first?.id == "PLaaa")
        #expect(playlists.first?.title == "Road Trip")
        #expect(playlists.last?.title == "Focus")
        #expect(playlists.last?.thumbnailURL?.absoluteString == "https://img/x")
    }

    @Test("Empty / missing renderer yields no playlists")
    func parsesEmpty() throws {
        #expect(AddToPlaylistParser.parse(try response(from: "{ }")).isEmpty)
    }
}
