//
//  WatchHistory.swift
//  YT Music
//
//  Reporting a play to YouTube Music's watch history. The player response carries
//  `videostatsPlaybackUrl` (fired once at start) and `videostatsWatchtimeUrl`
//  (reports accumulated listen time). Pinging both with the content-playback
//  nonce (`cpn`) that also tagged the streamed media is what makes a track show
//  up in the signed-in user's history — mirroring yt-dlp's `--mark-watched` and
//  the real web player's stats beacons.
//

import Foundation

/// Registers a track as played so it lands in the user's YT Music history.
/// Abstracted so PlayerState can be driven by a fake in tests (no network).
nonisolated protocol WatchHistoryReporting: Sendable {
    /// Fires the `playback` beacon once at the start of a play, using `cpn` (the
    /// nonce that also tags the streamed media). `position`/`length` are the live
    /// playback position and track length in seconds. No-op when signed out.
    func reportPlaybackStart(playbackURL: URL, cpn: String, position: Double, length: Double?) async

    /// Fires a `watchtime` heartbeat reporting the listener is at `position` of a
    /// `length`-second track — the signal that drives YT Music history. Called
    /// repeatedly as playback advances. No-op when signed out.
    func reportWatchtime(watchtimeURL: URL, cpn: String, position: Double, length: Double?) async
}

/// Pure helpers for building the history pings. Separated from the networking so
/// the URL construction can be unit-tested without a live request.
enum WatchHistory {
    /// The 64-symbol alphabet YouTube's player uses for the content-playback
    /// nonce (a-z, A-Z, 0-9, `-`, `_`).
    static let cpnAlphabet = Array(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )

    /// A fresh 16-character content-playback nonce identifying this play.
    static func generateCPN() -> String {
        String((0..<16).map { _ in cpnAlphabet[Int.random(in: 0..<cpnAlphabet.count)] })
    }

    /// Tags the googlevideo media URL with the content-playback nonce. The real
    /// player appends `cpn` to the stream it fetches so YouTube can correlate the
    /// served bytes with the stats pings that carry the same nonce — that
    /// correlation is what makes the play count toward history. Returns the
    /// original URL unchanged if it can't be parsed.
    static func appendingCPN(to streamURL: URL, cpn: String) -> URL {
        guard var components = URLComponents(url: streamURL, resolvingAgainstBaseURL: false) else {
            return streamURL
        }
        components.queryItems = setting(components.queryItems ?? [], "cpn", cpn)
        return components.url ?? streamURL
    }

    /// Builds the stats `playback` URL — the start-of-play beacon. `client` carries
    /// the WEB_REMIX client-identity params (`c`, `cver`, …) to tag the play as a
    /// Music listen. Returns nil if `base` can't be parsed.
    static func playbackURL(base: URL, cpn: String, position: Double, length: Double?,
                            client: [String: String] = [:]) -> URL? {
        statsURL(base: base, cpn: cpn, position: position, length: length, watchtime: false, client: client)
    }

    /// Builds the stats `watchtime` URL — a position heartbeat that drives YT Music
    /// history. `client` carries the WEB_REMIX client-identity params.
    /// Returns nil if `base` can't be parsed.
    static func watchtimeURL(base: URL, cpn: String, position: Double, length: Double?,
                             client: [String: String] = [:]) -> URL? {
        statsURL(base: base, cpn: cpn, position: position, length: length, watchtime: true, client: client)
    }

    /// Shared builder for the playback / watchtime stats URLs. The base URL comes
    /// from a WEB_REMIX (music) player response. We preserve its params and inject:
    ///   • `cpn`      — this session's nonce (we generate it).
    ///   • `ver=2`    — tracking protocol version (added only if absent).
    ///   • `cmt`      — current media time (the live position, in seconds).
    ///   • `len`      — track length (added only if absent).
    ///   • `client`   — WEB_REMIX identity (`c=WEB_REMIX`, `cver`, `cplayer`, OS/
    ///                  browser descriptors). The base URL omits these, and without
    ///                  `c=WEB_REMIX` the play is filed as a generic YouTube watch
    ///                  rather than a Music listen. Added only if absent.
    ///
    /// We also force the host to **music.youtube.com**. YouTube returns the stats
    /// base on the generic `s.youtube.com` sink, and pinging that records a plain
    /// YouTube watch that never reaches YTM History. The music web client sends
    /// these beacons same-origin to `music.youtube.com/api/stats/...` (confirmed by
    /// captured traffic), which is the music-history sink.
    ///
    /// The watchtime heartbeat additionally reports the live position and state:
    ///   • `st=et=position` — a point-in-time sample (the real client sends both
    ///                        equal to the current position, not a 0→pos range).
    ///   • `state=playing`.
    private static func statsURL(base: URL, cpn: String, position: Double,
                                 length: Double?, watchtime: Bool, client: [String: String]) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        components.host = "music.youtube.com"
        var items = components.queryItems ?? []
        items = setting(items, "cpn", cpn)
        if !items.contains(where: { $0.name == "ver" }) {
            items.append(URLQueryItem(name: "ver", value: "2"))
        }
        items = setting(items, "cmt", seconds(position))
        if let length, length > 0, !items.contains(where: { $0.name == "len" }) {
            items.append(URLQueryItem(name: "len", value: seconds(length)))
        }
        // Client identity (sorted for deterministic output), added only if the base
        // didn't already supply the key.
        for (key, value) in client.sorted(by: { $0.key < $1.key })
        where !items.contains(where: { $0.name == key }) {
            items.append(URLQueryItem(name: key, value: value))
        }
        if watchtime {
            items = setting(items, "st", seconds(position))
            items = setting(items, "et", seconds(position))
            items = setting(items, "state", "playing")
        }
        components.queryItems = items
        return components.url
    }

    /// Formats a seconds value the way the player does (millisecond precision,
    /// e.g. `128.067`).
    private static func seconds(_ value: Double) -> String {
        String(format: "%.3f", max(0, value))
    }

    /// Returns `items` with any existing entries named `name` removed and a single
    /// `name=value` appended — so callers overwrite rather than duplicate keys.
    private static func setting(_ items: [URLQueryItem], _ name: String, _ value: String) -> [URLQueryItem] {
        items.filter { $0.name != name } + [URLQueryItem(name: name, value: value)]
    }
}
