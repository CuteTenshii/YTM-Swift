import Foundation
import Testing
@testable import YT_Music

@Suite struct DescriptionLinkerTests {
    private func links(_ text: String) -> [String] {
        DescriptionLinker.attributed(text).runs.compactMap { $0.link?.absoluteString }
    }

    @Test func linksMentionsAndURLs() {
        let found = links("Follow @oasis or visit https://example.com/a now.")
        #expect(found == ["https://www.youtube.com/@oasis", "https://example.com/a"])
    }

    @Test func mentionDropsTrailingPunctuationAndIgnoresEmails() {
        #expect(links("Thanks @band.") == ["https://www.youtube.com/@band"])
        #expect(!links("mail me@host.com").contains { $0.contains("youtube.com") })
    }

    @Test func routesYouTubeLinksInApp() throws {
        func target(_ s: String) throws -> MusicLinks.Target? { MusicLinks.target(for: try #require(URL(string: s))) }
        #expect(try target("https://www.youtube.com/@oasis") == .handle("@oasis"))
        #expect(try target("https://music.youtube.com/playlist?list=PL123")
            == .entity(EntityLink(name: "", browseId: "VLPL123", kind: .playlist)))
        #expect(try target("https://music.youtube.com/channel/UCabc")
            == .entity(EntityLink(name: "", browseId: "UCabc", kind: .artist)))
        #expect(try target("https://music.youtube.com/watch?v=abc&list=PL9")
            == .watch(videoId: "abc", playlistId: "PL9"))
        #expect(try target("https://www.youtube.com/watch?v=abc") == .watch(videoId: "abc", playlistId: nil))
        #expect(try target("https://example.com/playlist?list=PL1") == nil)
    }
}
