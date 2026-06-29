//
//  MusicLinksTests.swift
//  YT MusicTests
//
//  Tests for canonical share-URL construction.
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Music links")
struct MusicLinksTests {

    @Test("Video id produces a watch URL")
    func videoURL() {
        let url = MusicLinks.url(videoId: "abc123", playlistId: nil, browseId: nil)
        #expect(url?.absoluteString == "https://music.youtube.com/watch?v=abc123")
    }

    @Test("Video id with playlist appends the list")
    func videoWithPlaylist() {
        let url = MusicLinks.url(videoId: "abc123", playlistId: "PL42", browseId: nil)
        #expect(url?.absoluteString == "https://music.youtube.com/watch?v=abc123&list=PL42")
    }

    @Test("Playlist id produces a playlist URL")
    func playlistURL() {
        let url = MusicLinks.url(videoId: nil, playlistId: "PLxyz", browseId: nil)
        #expect(url?.absoluteString == "https://music.youtube.com/playlist?list=PLxyz")
    }

    @Test("VL-prefixed browse id maps to a playlist link")
    func vlBrowseMapsToPlaylist() {
        let url = MusicLinks.url(videoId: nil, playlistId: nil, browseId: "VLPLabc")
        #expect(url?.absoluteString == "https://music.youtube.com/playlist?list=PLabc")
    }

    @Test("Other browse ids produce a browse URL")
    func browseURL() {
        let url = MusicLinks.url(videoId: nil, playlistId: nil, browseId: "UCchannel")
        #expect(url?.absoluteString == "https://music.youtube.com/browse/UCchannel")
    }

    @Test("No identifiers yields nil")
    func noIdentifiers() {
        #expect(MusicLinks.url(videoId: nil, playlistId: nil, browseId: nil) == nil)
    }
}
