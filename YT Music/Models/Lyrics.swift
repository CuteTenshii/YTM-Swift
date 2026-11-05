//
//  Lyrics.swift
//  YT Music
//
//  View-facing model for a track's lyrics, as served by YouTube Music's lyrics
//  tab (plain text) or LRCLIB (which may also provide time-synced LRC lines).
//

import Foundation

nonisolated struct LyricLine: Sendable, Equatable, Identifiable {
    var time: Double
    var text: String
    /// Folds in the ordinal: lyric text repeats (choruses, blank lines).
    var id: Int
    var words: [TimedWord] = []
    /// Content end (richsync `te`); tells a real interlude from a line still being sung.
    var end: Double? = nil
}

nonisolated struct TimedWord: Sendable, Equatable {
    var time: Double
    var text: String
}

struct Lyrics: Sendable, Equatable {
    var text: String
    var source: String?
    var lines: [LyricLine] = []

    var isSynced: Bool { !lines.isEmpty }
}

nonisolated enum LyricsFocus: Equatable {
    case none
    case line(Int)
    case interlude(before: Int, progress: Double)

    static let interludeThreshold = 6.0
    static let assumedLineDuration = 6.0

    static func resolve(_ lines: [LyricLine], at now: Double) -> LyricsFocus {
        guard !lines.isEmpty else { return .none }
        let pending = lines.firstIndex { $0.time > now }
        let currentIndex: Int? = if let pending { pending == 0 ? nil : pending - 1 } else { lines.count - 1 }

        if let pending {
            let gapStart = currentIndex.map { contentEnd(of: $0, in: lines) } ?? 0
            let gap = lines[pending].time - gapStart
            if gap >= interludeThreshold, now >= gapStart {
                let progress = gap > 0 ? (now - gapStart) / gap : 1
                return .interlude(before: pending, progress: min(max(progress, 0), 1))
            }
        }
        return currentIndex.map(LyricsFocus.line) ?? .none
    }

    private static func contentEnd(of i: Int, in lines: [LyricLine]) -> Double {
        if let end = lines[i].end { return end }
        if let lastWord = lines[i].words.last?.time { return lastWord }
        let nextStart = i + 1 < lines.count ? lines[i + 1].time : .greatestFiniteMagnitude
        return min(lines[i].time + assumedLineDuration, nextStart)
    }
}

nonisolated enum LyricsProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case youtubeMusic
    case lrclib
    case musixmatch

    var id: Self { self }

    var label: String {
        switch self {
        case .youtubeMusic: "YouTube Music"
        case .lrclib:       "LRCLIB"
        case .musixmatch:   "Musixmatch"
        }
    }
}

nonisolated struct LyricsQuery: Sendable, Equatable {
    var videoId: String
    var title: String
    var artist: String
    var album: String
    var duration: Double?
}
