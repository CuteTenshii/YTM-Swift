//
//  InnerTubeClient.swift
//  YT Music
//
//  Minimal native client for YouTube's private InnerTube API, configured as the
//  WEB_REMIX (YouTube Music web) client. No official API exists, so we send the
//  same context object and headers the web player uses.
//
//  This is unauthenticated: the home feed returns generic recommendations.
//  Personalized results would require forwarding the user's SAPISID cookie and
//  computing the Authorization hash — out of scope for this slice.
//

import Foundation

enum InnerTubeError: LocalizedError {
    case badStatus(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): "YouTube Music returned HTTP \(code)."
        case .emptyResponse:       "YouTube Music returned an empty response."
        }
    }
}

/// Minimal decode target for action endpoints (subscribe, like) — we only care
/// that the request succeeded (a non-2xx throws before we get here).
private nonisolated struct EmptyActionResponse: Decodable {}

/// The signed-in user's rating of a track, mirroring YT Music's like/dislike UI.
nonisolated enum LikeStatus: String, Codable, Sendable {
    case indifferent
    case liked
    case disliked
}

/// Sets a track's like rating, and reads its current rating. Abstracted so
/// PlayerState can be driven by a fake in tests (no network).
protocol LikeProviding: Sendable {
    func setLikeStatus(videoId: String, status: LikeStatus) async throws
    func likeStatus(for videoId: String) async throws -> LikeStatus
}

extension InnerTubeClient: LikeProviding {}

nonisolated final class InnerTubeClient: Sendable, WatchHistoryReporting {
    static let shared = InnerTubeClient()

    // Public WEB_REMIX client constants (these ship in the YT Music web bundle).
    private let apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
    private let clientName = "WEB_REMIX"
    private let clientVersion = "1.20260623.13.00"
    private let baseURL = URL(string: "https://music.youtube.com/youtubei/v1/")!
    private let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
            + "(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Loads the YouTube Music home feed (`FEmusic_home`).
    func homeFeed() async throws -> HomeFeed {
        let response: BrowseResponse = try await post(
            "browse",
            body: ["browseId": "FEmusic_home"]
        )
        return HomeFeedParser.parse(response)
    }

    /// Loads the YouTube Music explore landing page (`FEmusic_explore`): new
    /// releases, charts, trending, and top music videos.
    func explore() async throws -> [HomeShelf] {
        let response: BrowseResponse = try await post(
            "browse",
            body: ["browseId": "FEmusic_explore"]
        )
        return ExploreParser.parse(response)
    }

    /// Runs a YouTube Music search, returning result shelves grouped by category
    /// ("Songs", "Albums", "Artists", …). An empty/blank query yields no shelves.
    /// Pass a `filter` other than `.all` to scope results to a single type, in
    /// which case YouTube returns its own pre-grouped, server-titled shelves.
    func search(_ query: String, filter: SearchFilter = .all) async throws -> [HomeShelf] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var body: [String: Any] = ["query": trimmed]
        if let params = filter.params { body["params"] = params }
        let response: SearchResponse = try await post("search", body: body)
        return SearchParser.parse(response)
    }

    /// Loads an album / playlist / artist page for the given browse id.
    func entity(_ destination: EntityDestination) async throws -> EntityPage {
        let response: EntityBrowseResponse = try await post(
            "browse",
            body: ["browseId": destination.browseId]
        )
        return EntityPageParser.parse(response, fallback: destination)
    }

    /// Loads the signed-in user's library landing page (requires auth).
    func library() async throws -> [HomeShelf] {
        let response: BrowseResponse = try await post(
            "browse",
            body: ["browseId": "FEmusic_library_landing"]
        )
        return LibraryParser.parse(response)
    }

    /// Loads the signed-in user's account info (name / handle / avatar). Returns
    /// nil when signed out (the response carries no account header).
    func accountInfo() async throws -> AccountInfo? {
        let response: AccountMenuResponse = try await post("account/account_menu", body: [:])
        return AccountInfoParser.parse(response)
    }

    /// Loads playback streams for a video. The `signatureTimestamp` (extracted
    /// from base.js) must match the player JS used to decipher the result.
    func player(videoId: String, signatureTimestamp: String?) async throws -> PlayerResponse {
        var body: [String: Any] = [
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true,
        ]
        if let signatureTimestamp, let sts = Int(signatureTimestamp) {
            body["playbackContext"] = [
                "contentPlaybackContext": ["signatureTimestamp": sts]
            ]
        }
        return try await post("player", body: body)
    }

    /// Fetches an endless radio queue seeded from a video (the "Start radio"
    /// action). The queue's first entry is the seed track itself.
    func radio(for videoId: String) async throws -> [Track] {
        let response: WatchNextResponse = try await post(
            "next",
            body: [
                "videoId": videoId,
                "playlistId": "RDAMVM\(videoId)",   // RDAMVM<id> = this song's radio
                "isAudioOnly": true,
                "enablePersistentPlaylistPanel": true,
                "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
            ]
        )
        return WatchNextParser.parse(response)
    }

    /// Subscribes to or unsubscribes from a channel (artist). Requires auth —
    /// the request is a no-op server-side without the signed-in session headers.
    /// Throws on a non-2xx status so callers can keep the previous UI state.
    func setSubscription(channelId: String, params: String?, subscribe: Bool) async throws {
        let endpoint = subscribe ? "subscription/subscribe" : "subscription/unsubscribe"
        var body: [String: Any] = ["channelIds": [channelId]]
        if let params { body["params"] = params }
        let _: EmptyActionResponse = try await post(endpoint, body: body)
    }

    /// Sets the signed-in user's like rating for a track via the `like/*`
    /// endpoints. Requires auth — a no-op server-side without the session
    /// headers. Throws on a non-2xx status so callers can revert the UI.
    func setLikeStatus(videoId: String, status: LikeStatus) async throws {
        let endpoint = switch status {
        case .liked:       "like/like"
        case .disliked:    "like/dislike"
        case .indifferent: "like/removelike"
        }
        let _: EmptyActionResponse = try await post(
            endpoint,
            body: ["target": ["videoId": videoId]]
        )
    }

    /// Adds or removes a playlist from the signed-in user's library. YT Music's
    /// "Add to library" / "Remove from library" actions are the same `like/*`
    /// endpoints used to rate a track, but applied to a `playlistId` target.
    /// Requires auth — a no-op server-side without the session headers. Throws
    /// on a non-2xx status so callers can revert the UI.
    func setPlaylistSaved(playlistId: String, saved: Bool) async throws {
        let endpoint = saved ? "like/like" : "like/removelike"
        let _: EmptyActionResponse = try await post(
            endpoint,
            body: ["target": ["playlistId": playlistId]]
        )
    }

    /// Reads the signed-in user's current like rating for a track from the
    /// watch-next overlay. Skips the network round-trip when signed out (the
    /// rating is per-account, so it's always `.indifferent` anonymously).
    func likeStatus(for videoId: String) async throws -> LikeStatus {
        guard await CredentialStore.shared.isSignedIn else { return .indifferent }
        let response: WatchNextResponse = try await post("next", body: ["videoId": videoId])
        return WatchNextParser.likeStatus(response, expecting: videoId)
    }

    /// Fires the `playback` beacon once at the start of a play. No-op when signed
    /// out — history is per-account, so an anonymous ping does nothing.
    func reportPlaybackStart(playbackURL: URL, cpn: String, position: Double, length: Double?) async {
        let headers = await CredentialStore.shared.requestHeaders()
        guard !headers.isEmpty else {
            PlaybackLog.note("history: skipped (signed out)")
            return
        }
        if let url = WatchHistory.playbackURL(base: playbackURL, cpn: cpn, position: position, length: length) {
            await ping(url, credentialHeaders: headers, label: "playback")
        }
    }

    /// Fires a `watchtime` heartbeat reporting the live playback position — the
    /// signal that drives YT Music history. No-op when signed out.
    func reportWatchtime(watchtimeURL: URL, cpn: String, position: Double, length: Double?) async {
        let headers = await CredentialStore.shared.requestHeaders()
        guard !headers.isEmpty else { return }
        if let url = WatchHistory.watchtimeURL(base: watchtimeURL, cpn: cpn, position: position, length: length) {
            await ping(url, credentialHeaders: headers, label: "watchtime")
        }
    }

    /// Fires a single stats beacon (GET) with the client + session headers.
    private func ping(_ url: URL, credentialHeaders: [String: String], label: String) async {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyClientHeaders(to: &request)
        for (header, value) in credentialHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }

        do {
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            PlaybackLog.note("history: \(label) → HTTP \(code) · \(url.absoluteString)")
        } catch {
            PlaybackLog.problem("history \(label) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Request plumbing

    private func post<T: Decodable>(
        _ endpoint: String,
        body: [String: Any]
    ) async throws -> T {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "prettyPrint", value: "false"),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyClientHeaders(to: &request)

        var payload = body
        payload["context"] = context()
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Attach the signed-in session, if any (Cookie + SAPISIDHASH). Empty when
        // signed out, so unauthenticated requests are unaffected.
        for (header, value) in await CredentialStore.shared.requestHeaders() {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let (data, urlResponse) = try await session.data(for: request)

        if let http = urlResponse as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw InnerTubeError.badStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw InnerTubeError.emptyResponse }

        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Sets the WEB_REMIX client headers common to every request (the JSON
    /// `Content-Type` is set per-request since stats pings are GETs).
    private func applyClientHeaders(to request: inout URLRequest) {
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue(clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    }

    /// The InnerTube `context.client` block identifying us as the YT Music web app.
    private func context() -> [String: Any] {
        [
            "client": [
                "clientName": clientName,
                "clientVersion": clientVersion,
                "hl": "en",
                "gl": "US",
            ],
            "user": [:],
        ]
    }
}
