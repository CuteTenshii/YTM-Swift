//
//  WatchHistory.swift
//  YT Music
//

import Foundation

nonisolated protocol WatchHistoryReporting: Sendable {
    func reportPlaybackStart(playbackURL: URL, cpn: String, position: Double, length: Double?) async

    func reportWatchtime(watchtimeURL: URL, cpn: String, position: Double, length: Double?) async
}

enum WatchHistory {
    /// The 64-symbol alphabet of the player's content-playback nonce.
    static let cpnAlphabet = Array(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )

    static func generateCPN() -> String {
        String((0..<16).map { _ in cpnAlphabet[Int.random(in: 0..<cpnAlphabet.count)] })
    }

    /// The real player appends `cpn` so YouTube correlates the media with the stats pings.
    static func appendingCPN(to streamURL: URL, cpn: String) -> URL {
        guard var components = URLComponents(url: streamURL, resolvingAgainstBaseURL: false) else {
            return streamURL
        }
        components.queryItems = setting(components.queryItems ?? [], "cpn", cpn)
        return components.url ?? streamURL
    }

    /// `client` carries the WEB_REMIX identity params; without `c=WEB_REMIX` the play files as a generic YouTube watch.
    static func playbackURL(base: URL, cpn: String, position: Double, length: Double?,
                            client: [String: String] = [:]) -> URL? {
        statsURL(base: base, cpn: cpn, position: position, length: length, watchtime: false, client: client)
    }

    static func watchtimeURL(base: URL, cpn: String, position: Double, length: Double?,
                             client: [String: String] = [:]) -> URL? {
        statsURL(base: base, cpn: cpn, position: position, length: length, watchtime: true, client: client)
    }

    /// Host is forced to music.youtube.com; the s.youtube.com sink never reaches YTM History.
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

    private static func seconds(_ value: Double) -> String {
        String(format: "%.3f", max(0, value))
    }

    private static func setting(_ items: [URLQueryItem], _ name: String, _ value: String) -> [URLQueryItem] {
        items.filter { $0.name != name } + [URLQueryItem(name: name, value: value)]
    }
}
