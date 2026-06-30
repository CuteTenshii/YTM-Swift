//
//  LastfmScrobbler.swift
//  YT Music
//
//  The Last.fm scrobbling service behind `LastfmPlugin`. Split into:
//
//   • Pure, `nonisolated`, unit-tested pieces — the API signature (md5 of the
//     sorted params + shared secret), the scrobble-eligibility rule, and a
//     `ScrobbleTracker` state machine that turns the discrete PlaybackSnapshot
//     stream into `updateNowPlaying`/`scrobble` actions.
//   • `LastfmClient` — the network/auth/Keychain layer (the untested realtime
//     part, like DiscordRPC's socket glue).
//
//  Last.fm API reference: https://www.last.fm/api . Scrobbling needs a registered
//  API account (key + shared secret); the desktop auth flow is getToken → user
//  authorizes in the browser → getSession returns a permanent session key.
//

import Foundation
import CryptoKit

// MARK: - Models

/// A track being considered for scrobbling. `startedAt` is the unix timestamp the
/// track began playing — Last.fm uses it as the scrobble time.
nonisolated struct ScrobbleTrack: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var startedAt: Int
}

/// The actions the tracker asks the client to perform.
nonisolated enum ScrobbleAction: Equatable, Sendable {
    case nowPlaying(ScrobbleTrack)
    case scrobble(ScrobbleTrack)
}

/// A connected Last.fm account: the username (for display) and the permanent
/// session key used to sign authenticated calls.
nonisolated struct LastfmSession: Codable, Equatable, Sendable {
    var username: String
    var key: String
}

// MARK: - Signature & eligibility (pure, tested)

nonisolated enum LastfmSignature {
    /// Last.fm's `api_sig`: sort params by name, concatenate `name+value` for each
    /// (excluding `format`/`callback`), append the shared secret, md5-hex it.
    static func sign(_ params: [String: String], secret: String) -> String {
        let joined = params
            .filter { $0.key != "format" && $0.key != "callback" }
            .sorted { $0.key < $1.key }
            .map { $0.key + $0.value }
            .joined()
        let digest = Insecure.MD5.hash(data: Data((joined + secret).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Last.fm's scrobble rule: the track must be longer than 30 seconds and have
/// been played for at least half its length, or 4 minutes, whichever is shorter.
nonisolated func lastfmScrobbleEligible(playedSeconds: Double, duration: Double) -> Bool {
    guard duration > 30 else { return false }
    return playedSeconds >= min(duration / 2, 240)
}

// MARK: - Tracker (pure state machine, tested)

/// Turns the app's discrete `PlaybackSnapshot` stream (which fires on track and
/// play/pause changes, not on a timer) into Last.fm actions. It accumulates
/// played time from wall-clock deltas between snapshots, sends `nowPlaying` when
/// a track starts, and `scrobble` once a track has been played enough — finalized
/// on track change / stop, or mid-track when a pause makes it eligible.
nonisolated struct ScrobbleTracker {
    private struct Current {
        var videoId: String
        var track: ScrobbleTrack
        var accumulated: Double
        var playingSince: Date?   // wall clock playback (re)started; nil = paused
        var scrobbled: Bool
    }

    private var current: Current?

    /// Feeds one snapshot (nil = playback stopped) and returns the actions to run.
    mutating func update(_ snapshot: PlaybackSnapshot?, now: Date) -> [ScrobbleAction] {
        guard let snapshot else {
            let actions = finalize(now: now)
            current = nil
            return actions
        }

        var actions: [ScrobbleAction] = []

        if current?.videoId != snapshot.videoId {
            // New track: finalize the previous one, then start tracking this one.
            actions += finalize(now: now)
            let track = ScrobbleTrack(
                title: snapshot.title,
                artist: snapshot.artist,
                album: snapshot.album,
                duration: snapshot.duration,
                startedAt: Int(now.timeIntervalSince1970)
            )
            current = Current(
                videoId: snapshot.videoId,
                track: track,
                accumulated: 0,
                playingSince: snapshot.isPlaying ? now : nil,
                scrobbled: false
            )
            if snapshot.isPlaying { actions.append(.nowPlaying(track)) }
            return actions
        }

        // Same track: settle a play/pause transition and re-check eligibility.
        guard var c = current else { return actions }
        if let since = c.playingSince {
            c.accumulated += max(0, now.timeIntervalSince(since))
        }
        c.playingSince = snapshot.isPlaying ? now : nil
        if snapshot.duration > c.track.duration { c.track.duration = snapshot.duration }
        if !c.scrobbled, lastfmScrobbleEligible(playedSeconds: c.accumulated, duration: c.track.duration) {
            c.scrobbled = true
            actions.append(.scrobble(c.track))
        }
        current = c
        return actions
    }

    /// Settles the in-flight track's played time and scrobbles it if it qualifies.
    private mutating func finalize(now: Date) -> [ScrobbleAction] {
        guard var c = current else { return [] }
        if let since = c.playingSince {
            c.accumulated += max(0, now.timeIntervalSince(since))
            c.playingSince = nil
        }
        current = c
        guard !c.scrobbled, lastfmScrobbleEligible(playedSeconds: c.accumulated, duration: c.track.duration) else {
            return []
        }
        c.scrobbled = true
        current = c
        return [.scrobble(c.track)]
    }
}

// MARK: - Network / auth client

/// Talks to the Last.fm API: signs requests, runs the desktop auth handshake, and
/// fires `updateNowPlaying` / `scrobble`. The session key is persisted in the
/// Keychain. Off the main actor so the plugin can fire-and-forget into it.
actor LastfmClient {
    /// A Last.fm API account (key + shared secret) from https://www.last.fm/api/account/create .
    /// Replace these placeholders with your own to enable scrobbling.
    static let apiKey = "YOUR_LASTFM_API_KEY"
    static let secret = "YOUR_LASTFM_SHARED_SECRET"

    private static let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    private static let keychainService = "moe.tenshii.YT-Music"
    private static let keychainAccount = "lastfm-session"

    private let apiKey: String
    private let secret: String
    private let session: URLSession
    private var account: LastfmSession?

    init(apiKey: String = LastfmClient.apiKey,
         secret: String = LastfmClient.secret,
         session: URLSession = .shared) {
        self.apiKey = apiKey
        self.secret = secret
        self.session = session
        self.account = Self.loadSession()
    }

    var isConfigured: Bool { apiKey != "YOUR_LASTFM_API_KEY" && !apiKey.isEmpty }
    var currentSession: LastfmSession? { account }

    // MARK: Auth

    /// Step 1: fetch an unauthorized request token to send the user to the browser.
    func requestToken() async throws -> String {
        let response = try await call(["method": "auth.getToken"], signed: true)
        guard let token = response["token"] as? String else { throw LastfmError.malformedResponse }
        return token
    }

    /// The URL the user opens to authorize `token` against this API account.
    nonisolated func authorizationURL(token: String) -> URL? {
        var components = URLComponents(string: "https://www.last.fm/api/auth/")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "token", value: token),
        ]
        return components?.url
    }

    /// Step 2 (after the user authorizes): exchange the token for a session key.
    func completeAuthorization(token: String) async throws -> LastfmSession {
        let response = try await call(["method": "auth.getSession", "token": token], signed: true)
        guard let session = response["session"] as? [String: Any],
              let key = session["key"] as? String,
              let name = session["name"] as? String else { throw LastfmError.malformedResponse }
        let account = LastfmSession(username: name, key: key)
        self.account = account
        Self.saveSession(account)
        return account
    }

    func disconnect() {
        account = nil
        Self.deleteSession()
    }

    // MARK: Scrobbling

    func updateNowPlaying(_ track: ScrobbleTrack) async {
        guard let account else { return }
        var params = Self.trackParams(track, sessionKey: account.key)
        params["method"] = "track.updateNowPlaying"
        _ = try? await call(params, signed: true)
    }

    func scrobble(_ track: ScrobbleTrack) async {
        guard let account else { return }
        var params = Self.trackParams(track, sessionKey: account.key)
        params["method"] = "track.scrobble"
        params["timestamp"] = String(track.startedAt)
        _ = try? await call(params, signed: true)
    }

    private static func trackParams(_ track: ScrobbleTrack, sessionKey: String) -> [String: String] {
        var params = [
            "track": track.title,
            "artist": track.artist,
            "sk": sessionKey,
        ]
        if !track.album.isEmpty { params["album"] = track.album }
        if track.duration > 0 { params["duration"] = String(Int(track.duration.rounded())) }
        return params
    }

    // MARK: Request plumbing

    /// Signs (optionally) and POSTs a form-encoded API call, returning the decoded
    /// JSON object. Throws `LastfmError.api` on a Last.fm error payload.
    @discardableResult
    private func call(_ params: [String: String], signed: Bool) async throws -> [String: Any] {
        guard isConfigured else { throw LastfmError.notConfigured }

        var fields = params
        fields["api_key"] = apiKey
        if signed { fields["api_sig"] = LastfmSignature.sign(fields, secret: secret) }
        fields["format"] = "json"

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields)

        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LastfmError.malformedResponse
        }
        if let code = json["error"] as? Int {
            throw LastfmError.api(code: code, message: json["message"] as? String ?? "Last.fm error")
        }
        return json
    }

    private static func formEncode(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    // MARK: Keychain

    static func loadSession() -> LastfmSession? {
        guard let data = Keychain.get(service: keychainService, account: keychainAccount) else { return nil }
        return try? JSONDecoder().decode(LastfmSession.self, from: data)
    }

    private static func saveSession(_ session: LastfmSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        Keychain.set(data, service: keychainService, account: keychainAccount)
    }

    private static func deleteSession() {
        Keychain.delete(service: keychainService, account: keychainAccount)
    }
}

nonisolated enum LastfmError: Error, LocalizedError {
    case notConfigured
    case malformedResponse
    case api(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Last.fm API key not configured."
        case .malformedResponse:
            return "Unexpected response from Last.fm."
        case .api(let code, let message):
            return "Last.fm error \(code): \(message)"
        }
    }
}
