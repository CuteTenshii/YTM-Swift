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

nonisolated final class InnerTubeClient: Sendable {
    static let shared = InnerTubeClient()

    // Public WEB_REMIX client constants (these ship in the YT Music web bundle).
    private let apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
    private let clientName = "WEB_REMIX"
    private let clientVersion = "1.20240403.01.00"
    private let baseURL = URL(string: "https://music.youtube.com/youtubei/v1/")!

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
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue(clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                + "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

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
