//
//  MusixmatchClient.swift
//  YT Music
//

import Foundation

actor MusixmatchClient: LyricsProviding {
    static let shared = MusixmatchClient()

    private let session: URLSession
    private let base = URL(string: "https://apic-desktop.musixmatch.com/ws/1.1/")!
    private let appId = "web-desktop-app-v1.0"
    private let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/120.0 Safari/537.36"

    /// Desktop user token, fetched once and reused.
    private var cachedToken: String?

    init(session: URLSession? = nil) {
        self.session = session ?? NetworkSession.make()
    }

    func lyrics(for query: LyricsQuery) async throws -> Lyrics? {
        let title = query.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !query.artist.isEmpty else { return nil }
        let token = try await token()

        // Match the track first so richsync can be requested by id.
        var match = [
            URLQueryItem(name: "q_track", value: query.title),
            URLQueryItem(name: "q_artist", value: query.artist),
        ]
        if let duration = query.duration, duration > 0 {
            match.append(URLQueryItem(name: "q_duration", value: String(Int(duration.rounded()))))
        }
        guard let matched: MatchBody = try await get("matcher.track.get", token: token, items: match),
              let track = matched.track, let id = track.commontrack_id
        else { return nil }
        let commontrack = [URLQueryItem(name: "commontrack_id", value: String(id))]

        // Preference: richsync, then subtitles, then plain.
        if track.has_richsync == 1,
           let body: RichSyncBody = try await get("track.richsync.get", token: token, items: commontrack),
           let raw = body.richsync?.richsync_body {
            let lines = MusixmatchRichSync.parse(raw)
            if !lines.isEmpty {
                return Lyrics(text: lines.map(\.text).joined(separator: "\n"),
                              source: String(format: String(localized: "lyrics.source"), "Musixmatch"), lines: lines)
            }
        }

        if track.has_subtitles == 1,
           let body: SubtitlesBody = try await get(
               "track.subtitles.get", token: token,
               items: commontrack + [URLQueryItem(name: "subtitle_format", value: "lrc")]),
           let raw = body.subtitle_list?.first?.subtitle?.subtitle_body, !raw.isEmpty {
            let lines = LRCParser.parse(raw)
            let text = lines.isEmpty ? raw : lines.map(\.text).joined(separator: "\n")
            return Lyrics(text: text, source: String(format: String(localized: "lyrics.source"), "Musixmatch"), lines: lines)
        }

        if let body: LyricsBody = try await get("track.lyrics.get", token: token, items: commontrack),
           let raw = body.lyrics?.lyrics_body, !raw.isEmpty {
            return Lyrics(text: raw, source: String(format: String(localized: "lyrics.source"), "Musixmatch"))
        }

        return nil
    }

    // MARK: - Token

    private func token() async throws -> String {
        if let cachedToken { return cachedToken }
        guard let body: TokenBody = try await get("token.get", token: nil, items: []),
              let token = body.user_token, token != "UpgradeOnlyUpgradeOnlyUpgradeOnlyUpgradeOnly"
        else { throw URLError(.userAuthenticationRequired) }
        cachedToken = token
        return token
    }

    // MARK: - Networking

    private func get<Body: Decodable>(
        _ endpoint: String, token: String?, items: [URLQueryItem]
    ) async throws -> Body? {
        var components = URLComponents(
            url: base.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "app_id", value: appId),
            URLQueryItem(name: "format", value: "json"),
        ] + (token.map { [URLQueryItem(name: "usertoken", value: $0)] } ?? []) + items

        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // The desktop endpoints reject requests without this cookie present.
        request.setValue("AWSELB=0", forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        let envelope = try JSONDecoder().decode(Envelope<Body>.self, from: data)
        guard envelope.message.header?.status_code == 200 else { return nil }
        return envelope.message.body
    }

    // MARK: - Response shapes

    private struct Envelope<Body: Decodable>: Decodable {
        let message: Message
        struct Message: Decodable {
            let header: Header?
            let body: Body?

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                header = try container.decodeIfPresent(Header.self, forKey: .header)
                // Musixmatch returns `body: ""` when there is no result; treat as absent.
                body = try? container.decodeIfPresent(Body.self, forKey: .body)
            }

            private enum CodingKeys: String, CodingKey { case header, body }
        }
        struct Header: Decodable { let status_code: Int? }
    }

    private struct TokenBody: Decodable { let user_token: String? }

    private struct MatchBody: Decodable {
        let track: Track?
        struct Track: Decodable {
            let commontrack_id: Int?
            let has_richsync: Int?
            let has_subtitles: Int?
        }
    }

    private struct RichSyncBody: Decodable {
        let richsync: RichSync?
        struct RichSync: Decodable { let richsync_body: String? }
    }

    private struct SubtitlesBody: Decodable {
        let subtitle_list: [Item]?
        struct Item: Decodable { let subtitle: Subtitle? }
        struct Subtitle: Decodable { let subtitle_body: String? }
    }

    private struct LyricsBody: Decodable {
        let lyrics: Lyrics?
        struct Lyrics: Decodable { let lyrics_body: String? }
    }
}
