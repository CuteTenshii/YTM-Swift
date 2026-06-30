//
//  WatchHistoryTests.swift
//  YT MusicTests
//
//  Tests for the pure pieces of watch-history reporting: the content-playback
//  nonce generator and the stats-URL builders. The actual network ping is not
//  covered (it needs a live, authenticated request).
//

import Testing
import Foundation
@testable import YT_Music

@Suite("WatchHistory")
struct WatchHistoryTests {

    private func items(_ url: URL?) -> [URLQueryItem] {
        guard let url else { return [] }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    @Test("Generated CPN is 16 chars from the YouTube alphabet")
    func cpnShape() {
        let alphabet = Set(WatchHistory.cpnAlphabet)
        for _ in 0..<100 {
            let cpn = WatchHistory.generateCPN()
            #expect(cpn.count == 16)
            #expect(cpn.allSatisfy { alphabet.contains($0) })
        }
    }

    @Test("Appending the CPN tags the stream URL, keeping its existing query")
    func appendingCPN() {
        let stream = URL(string: "https://rr3---googlevideo.com/videoplayback?itag=140&sig=AAA")!
        let url = WatchHistory.appendingCPN(to: stream, cpn: "NONCE0123456789")
        let q = items(url)
        #expect(q.contains(URLQueryItem(name: "itag", value: "140")))
        #expect(q.contains(URLQueryItem(name: "sig", value: "AAA")))
        #expect(q.contains(URLQueryItem(name: "cpn", value: "NONCE0123456789")))
    }

    @Test("playbackURL routes to music.youtube.com, preserves base params, injects cpn/ver/cmt/len")
    func playbackURLBuild() throws {
        // Mirrors a real WEB_REMIX stats base on the generic s.youtube.com sink:
        // it already carries el/c/cver, and must be re-homed to music.youtube.com.
        let base = URL(string: "https://s.youtube.com/api/stats/playback?docid=abc&el=detailpage&c=WEB_REMIX")!
        let url = try #require(WatchHistory.playbackURL(base: base, cpn: "CPN", position: 5, length: 200))
        let q = items(url)

        #expect(url.host == "music.youtube.com")                              // re-homed to the music sink
        #expect(url.path == "/api/stats/playback")
        #expect(q.filter { $0.name == "el" } == [URLQueryItem(name: "el", value: "detailpage")])
        #expect(q.contains(URLQueryItem(name: "c", value: "WEB_REMIX")))
        #expect(q.contains(URLQueryItem(name: "docid", value: "abc")))
        #expect(q.contains(URLQueryItem(name: "cpn", value: "CPN")))
        #expect(q.contains(URLQueryItem(name: "ver", value: "2")))
        #expect(q.contains(URLQueryItem(name: "cmt", value: "5.000")))
        #expect(q.contains(URLQueryItem(name: "len", value: "200.000")))
        // The playback beacon carries no watchtime fields.
        #expect(!q.contains { $0.name == "st" })
        #expect(!q.contains { $0.name == "state" })
    }

    @Test("watchtimeURL sends st=et=cmt=position and state=playing")
    func watchtimeURLBuild() throws {
        let base = URL(string: "https://music.youtube.com/api/stats/watchtime?docid=abc")!
        let url = try #require(WatchHistory.watchtimeURL(base: base, cpn: "CPN", position: 5, length: 200))
        let q = items(url)

        #expect(q.contains(URLQueryItem(name: "cmt", value: "5.000")))
        #expect(q.contains(URLQueryItem(name: "st", value: "5.000")))
        #expect(q.contains(URLQueryItem(name: "et", value: "5.000")))
        #expect(q.contains(URLQueryItem(name: "state", value: "playing")))
        #expect(q.contains(URLQueryItem(name: "len", value: "200.000")))
    }

    @Test("Builders don't overwrite a ver the base already carries, and omit len when unknown")
    func preservesVerAndOptionalLen() throws {
        let base = URL(string: "https://s.youtube.com/api/stats/playback?ver=3&docid=abc")!
        let url = try #require(WatchHistory.playbackURL(base: base, cpn: "CPN", position: 1, length: nil))
        let q = items(url)
        #expect(q.filter { $0.name == "ver" } == [URLQueryItem(name: "ver", value: "3")])
        #expect(q.filter { $0.name == "cpn" } == [URLQueryItem(name: "cpn", value: "CPN")])
        #expect(!q.contains { $0.name == "len" })
    }
}
