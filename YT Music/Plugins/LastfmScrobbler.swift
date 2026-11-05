//
//  LastfmScrobbler.swift
//  YT Music
//
//

import Foundation
import OSLog
import CryptoKit

// MARK: - Models

/// `startedAt` is the unix timestamp Last.fm uses as the scrobble time.
nonisolated struct ScrobbleTrack: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var startedAt: Int
}

nonisolated enum ScrobbleAction: Equatable, Sendable {
    case nowPlaying(ScrobbleTrack)
    case scrobble(ScrobbleTrack)
}

nonisolated struct LastfmSession: Codable, Equatable, Sendable {
    var username: String
    var key: String
}

// MARK: - Signature & eligibility (pure, tested)

nonisolated enum LastfmSignature {
    /// `api_sig`: sorted `name+value` pairs (minus `format`/`callback`) + secret, md5-hex.
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

/// Scrobble rule: longer than 30s, played half its length or 4 minutes, whichever is shorter.
nonisolated func lastfmScrobbleEligible(playedSeconds: Double, duration: Double) -> Bool {
    guard duration > 30 else { return false }
    return playedSeconds >= min(duration / 2, 240)
}

// MARK: - Tracker (pure state machine, tested)

/// Turns snapshots into Last.fm actions, accumulating played time from wall-clock deltas.
nonisolated struct ScrobbleTracker {
    private struct Current {
        var videoId: String
        var track: ScrobbleTrack
        var accumulated: Double
        var playingSince: Date?   // wall clock playback (re)started; nil = paused
        var scrobbled: Bool
    }

    private var current: Current?

    mutating func update(_ snapshot: PlaybackSnapshot?, now: Date) -> [ScrobbleAction] {
        guard let snapshot else {
            let actions = finalize(now: now)
            current = nil
            return actions
        }

        var actions: [ScrobbleAction] = []

        if current?.videoId != snapshot.videoId {
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

/// Last.fm API client: signing, desktop auth, scrobbling; the account is persisted in the Keychain.
/// Scrobbling is a write: API key, shared secret and session key are all required.
actor LastfmClient {
    private static let log = Logger(category: "lastfm")
    private static let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    private static let keychainService = "moe.tenshii.YT-Music"
    private static let keychainAccount = "lastfm-account"

    nonisolated struct StoredAccount: Codable, Equatable, Sendable {
        var apiKey: String
        var secret: String
        var session: LastfmSession
    }

    private let session: URLSession
    private var account: StoredAccount?
    /// Captured at `requestToken`, reused by `completeAuthorization`.
    private var pending: (apiKey: String, secret: String)?

    init(session: URLSession? = nil) {
        self.session = session ?? NetworkSession.make()
        self.account = Self.loadAccount()
    }

    // MARK: Auth

    func requestToken(apiKey: String, secret: String) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sec = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !sec.isEmpty else { throw LastfmError.notConfigured }
        let response = try await call(["method": "auth.getToken"], apiKey: key, secret: sec)
        guard let token = response["token"] as? String else { throw LastfmError.malformedResponse }
        pending = (key, sec)
        return token
    }

    nonisolated func authorizationURL(apiKey: String, token: String) -> URL? {
        var components = URLComponents(string: "https://www.last.fm/api/auth/")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "token", value: token),
        ]
        return components?.url
    }

    func completeAuthorization(token: String) async throws -> LastfmSession {
        guard let pending else { throw LastfmError.notConfigured }
        let response = try await call(["method": "auth.getSession", "token": token],
                                      apiKey: pending.apiKey, secret: pending.secret)
        guard let session = response["session"] as? [String: Any] else {
            Self.log.problem("Last.fm getSession missing `session`: \(response)")
            throw LastfmError.malformedResponse
        }
        // Last.fm sometimes wraps text values as {"#text": "…"}.
        guard let sk = Self.string(session["key"]), !sk.isEmpty,
              let name = Self.string(session["name"]), !name.isEmpty else {
            Self.log.problem("Last.fm getSession unexpected shape: \(session)")
            throw LastfmError.malformedResponse
        }
        let account = StoredAccount(apiKey: pending.apiKey, secret: pending.secret,
                                    session: LastfmSession(username: name, key: sk))
        self.account = account
        self.pending = nil
        Self.saveAccount(account)
        return account.session
    }

    private static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let dict = value as? [String: Any], let s = dict["#text"] as? String { return s }
        return nil
    }

    func disconnect() {
        account = nil
        pending = nil
        Self.deleteAccount()
    }

    // MARK: Scrobbling

    func updateNowPlaying(_ track: ScrobbleTrack) async {
        guard let account else { return }
        var params = Self.trackParams(track, sessionKey: account.session.key)
        params["method"] = "track.updateNowPlaying"
        _ = try? await call(params, apiKey: account.apiKey, secret: account.secret)
    }

    func scrobble(_ track: ScrobbleTrack) async {
        guard let account else { return }
        var params = Self.trackParams(track, sessionKey: account.session.key)
        params["method"] = "track.scrobble"
        params["timestamp"] = String(track.startedAt)
        _ = try? await call(params, apiKey: account.apiKey, secret: account.secret)
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

    @discardableResult
    private func call(_ params: [String: String], apiKey: String, secret: String) async throws -> [String: Any] {
        var fields = params
        fields["api_key"] = apiKey
        fields["api_sig"] = LastfmSignature.sign(fields, secret: secret)
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

    static func loadSession() -> LastfmSession? { loadAccount()?.session }

    private static func loadAccount() -> StoredAccount? {
        guard let data = Keychain.get(service: keychainService, account: keychainAccount) else { return nil }
        return try? JSONDecoder().decode(StoredAccount.self, from: data)
    }

    private static func saveAccount(_ account: StoredAccount) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        Keychain.set(data, service: keychainService, account: keychainAccount)
    }

    private static func deleteAccount() {
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
            return String(localized: "plugins.lastfm.error.not_configured")
        case .malformedResponse:
            return String(localized: "plugins.lastfm.error.malformed")
        case .api(let code, let message):
            return String(format: String(localized: "plugins.lastfm.error.api"), code, message)
        }
    }
}
