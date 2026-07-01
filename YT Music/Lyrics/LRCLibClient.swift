//
//  LRCLibClient.swift
//  YT Music
//
//  A lyrics provider backed by LRCLIB (https://lrclib.net) — a free, open,
//  no-auth lyrics database. Matched by track metadata rather than a YouTube id:
//  an exact `get` (title + artist + album + duration) first, falling back to a
//  `search` by title/artist. We display the plain (untimed) lyrics.
//

import Foundation

nonisolated final class LRCLibClient: LyricsProviding, Sendable {
    static let shared = LRCLibClient()

    private let session: URLSession
    private let baseURL = URL(string: "https://lrclib.net/api/")!
    // LRCLIB asks clients to identify themselves in the User-Agent.
    private let userAgent = "YT Music (macOS; https://github.com/tenshii/YT-Music)"

    init(session: URLSession = .shared) {
        self.session = session
    }

    private struct LRCLibTrack: Decodable {
        let trackName: String?
        let artistName: String?
        let plainLyrics: String?
        let syncedLyrics: String?
        let instrumental: Bool?
    }

    func lyrics(for query: LyricsQuery) async throws -> Lyrics? {
        let title = query.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        // Prefer an exact metadata match; otherwise fall back to a text search.
        if let exact = try await exactMatch(query) { return exact }
        return try await searchMatch(query)
    }

    /// `GET /api/get` — an exact match on title + artist (+ album + duration).
    /// LRCLIB returns 404 when it has no exact match, which we treat as "none".
    private func exactMatch(_ query: LyricsQuery) async throws -> Lyrics? {
        guard !query.artist.isEmpty else { return nil }   // get requires an artist
        var items = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "artist_name", value: query.artist),
        ]
        if !query.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: query.album))
        }
        if let duration = query.duration, duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        guard let track: LRCLibTrack = try await get("get", query: items) else { return nil }
        return lyrics(from: track)
    }

    /// `GET /api/search` — a fuzzy text search; we take the first usable hit.
    private func searchMatch(_ query: LyricsQuery) async throws -> Lyrics? {
        let q = [query.title, query.artist].filter { !$0.isEmpty }.joined(separator: " ")
        let items = [URLQueryItem(name: "q", value: q)]
        guard let results: [LRCLibTrack] = try await get("search", query: items) else { return nil }
        return results.lazy.compactMap { self.lyrics(from: $0) }.first
    }

    /// Issues a GET and decodes the body, or returns nil for a non-200 (e.g. the
    /// 404 LRCLIB uses for "not found").
    private func get<T: Decodable>(_ endpoint: String, query items: [URLQueryItem]) async throws -> T? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func lyrics(from track: LRCLibTrack) -> Lyrics? {
        if track.instrumental == true {
            return Lyrics(text: "♪ Instrumental ♪", source: "LRCLIB")
        }
        let synced = track.syncedLyrics.map(LRCParser.parse) ?? []
        // Prefer the plain text for the fallback view; if only synced lyrics
        // exist, flatten them into plain text so there's always something.
        let plain = track.plainLyrics.flatMap { $0.isEmpty ? nil : $0 }
            ?? synced.map(\.text).joined(separator: "\n")
        guard !plain.isEmpty else { return nil }
        return Lyrics(text: plain, source: "Source: LRCLIB", lines: synced)
    }
}
