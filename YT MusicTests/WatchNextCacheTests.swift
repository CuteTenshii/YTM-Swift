//
//  WatchNextCacheTests.swift
//  YT MusicTests
//
//  Verifies like status and like count share one cached `next` request.
//

import Testing
import Foundation
@testable import YT_Music

nonisolated class CountingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests = 0
    static let body = Data("""
    {"playerOverlays":{"playerOverlayRenderer":{"videoActionBar":{"videoActionBarViewModel":
    {"buttons":[{"buttonViewModel":{"segmentedLikeDislikeButtonViewModel":
    {"likeCountEntity":{"likeCountIfIndifferentNumber":"7"}}}}]}}}}}
    """.utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Watch-next cache", .serialized)
struct WatchNextCacheTests {
    @Test("repeated like count lookups hit the cache, not the network")
    func sharesOneRequest() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CountingURLProtocol.self]
        let client = InnerTubeClient(session: URLSession(configuration: config))
        CountingURLProtocol.requests = 0

        #expect(try await client.likeCount(for: "vid") == 7)
        #expect(try await client.likeCount(for: "vid") == 7)
        #expect(CountingURLProtocol.requests == 1)
    }

    @Test("concurrent lookups for an uncached track share one request")
    func dedupesConcurrentLookups() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CountingURLProtocol.self]
        let client = InnerTubeClient(session: URLSession(configuration: config))
        CountingURLProtocol.requests = 0

        let counts = try await withThrowingTaskGroup(of: Int?.self) { group in
            for _ in 0..<5 { group.addTask { try await client.likeCount(for: "vid") } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(counts == Array(repeating: 7, count: 5))
        #expect(CountingURLProtocol.requests == 1)
    }
}
