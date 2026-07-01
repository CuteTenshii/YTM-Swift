//
//  PlaybackLog.swift
//  YT Music
//
//  Diagnostics for the (network-dependent, un-unit-testable) stream-resolution
//  pipeline. Logs every stage and, when signature extraction fails, dumps the
//  real base.js + excerpts around the anchors so the extraction patterns can be
//  fixed against the actual player instead of guessed.
//
//  View in Xcode's console, or Console.app filtered by subsystem
//  `moe.tenshii.YT-Music`, category `playback`.
//

import Foundation
import OSLog

nonisolated enum PlaybackLog {
    private static let logger = Logger(subsystem: "moe.tenshii.YT-Music", category: "playback")

    static func note(_ message: String) {
        logger.notice("🎵 \(message, privacy: .public)")
    }

    static func problem(_ message: String) {
        logger.error("🎵 ⚠️ \(message, privacy: .public)")
    }

    /// ~`radius` characters of `js` around the first occurrence of `marker`,
    /// for pasting back to diagnose extraction.
    static func excerpt(_ js: String, around marker: String, radius: Int = 160) -> String {
        guard let range = js.range(of: marker) else { return "«\(marker)» not present" }
        let start = js.index(range.lowerBound, offsetBy: -radius, limitedBy: js.startIndex) ?? js.startIndex
        let end = js.index(range.upperBound, offsetBy: radius, limitedBy: js.endIndex) ?? js.endIndex
        return String(js[start..<end])
    }

    /// Writes the player JS to Caches and returns the path so it can be shared.
    @discardableResult
    static func dumpBaseJS(_ js: String) -> String? {
        dump(js: js, to: "yt-base.js")
    }

    /// Writes an arbitrary response body to Caches under `name` and returns the
    /// path, for diagnosing network responses we can't reach from tests.
    @discardableResult
    static func dumpData(_ data: Data, to name: String) -> String? {
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        return dump(js: string, to: name)
    }

    private static func dump(js: String, to name: String) -> String? {
        guard let dir = try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let url = dir.appendingPathComponent(name)
        do {
            try js.write(to: url, atomically: true, encoding: .utf8)
            return url.path
        } catch {
            return nil
        }
    }
}
