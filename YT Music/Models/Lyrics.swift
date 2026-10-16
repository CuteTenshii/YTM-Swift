//
//  Lyrics.swift
//  YT Music
//
//  View-facing model for a track's lyrics, as served by YouTube Music's lyrics
//  tab (plain text) or LRCLIB (which may also provide time-synced LRC lines).
//

import Foundation

/// A single time-synced lyric line: the timestamp (seconds from the start of
/// the track) at which it becomes active, and its text.
nonisolated struct LyricLine: Sendable, Equatable, Identifiable {
    var time: Double
    var text: String
    /// Stable identity for `ForEach` / scroll targeting — lyric text repeats
    /// (choruses, blank lines), so the parser folds in the ordinal.
    var id: Int
    /// Per-word timings within the line, when the provider supplies them
    /// (Musixmatch richsync). Empty for line-level-only sources; drives the
    /// word-by-word "sweep" highlight.
    var words: [TimedWord] = []
    /// When the line's content ends (seconds), when known (richsync `te`). Used
    /// to decide when a following silence is a real instrumental interlude
    /// rather than the line still being sung.
    var end: Double? = nil
}

/// A word (or token) within a lyric line and the time it should light up.
nonisolated struct TimedWord: Sendable, Equatable {
    var time: Double
    var text: String
}

/// A track's lyrics text and its source attribution (e.g. "Source: Musixmatch").
///
/// When `lines` is non-empty the lyrics are time-synced (LRC) and the UI can
/// highlight and auto-scroll the current line; `text` is always the plain-text
/// fallback.
struct Lyrics: Sendable, Equatable {
    var text: String
    /// Attribution footer shown under the lyrics, if any.
    var source: String?
    /// Time-synced lines, when the provider supplies them; empty for plain
    /// lyrics.
    var lines: [LyricLine] = []

    /// Whether these lyrics carry per-line timings (karaoke-capable).
    var isSynced: Bool { !lines.isEmpty }
}

/// What the synced-lyrics UI should emphasize at a given playback time: the
/// currently-sung line, an instrumental interlude counting down to the next
/// line, or nothing yet (before the first line, no long intro).
nonisolated enum LyricsFocus: Equatable {
    case none
    case line(Int)
    /// A long gap before `before`; `progress` (0…1) fills the countdown dots.
    case interlude(before: Int, progress: Double)

    /// A gap this long (seconds) with no lyric content is treated as an
    /// instrumental interlude worth showing countdown dots for.
    static let interludeThreshold = 6.0
    /// For line-level lyrics (no per-word/end timing), assume a line runs at
    /// most this long before a following silence reads as an interlude.
    static let assumedLineDuration = 6.0

    /// Resolves the focus for `lines` at playback time `now`. A line stays
    /// active until its content ends (its last word / `end`, or the next line
    /// for line-level lyrics); a long silence after it — or a long intro —
    /// becomes an interlude counting down to the next line.
    static func resolve(_ lines: [LyricLine], at now: Double) -> LyricsFocus {
        guard !lines.isEmpty else { return .none }
        let pending = lines.firstIndex { $0.time > now }
        // The current line is the last one that has started (nil before the
        // first line / during a long intro).
        let currentIndex: Int? = if let pending { pending == 0 ? nil : pending - 1 } else { lines.count - 1 }

        if let pending {
            // The interlude spans from where the current line's content ends
            // (or track start, for the intro) to the next line's start.
            let gapStart = currentIndex.map { contentEnd(of: $0, in: lines) } ?? 0
            let gap = lines[pending].time - gapStart
            if gap >= interludeThreshold, now >= gapStart {
                let progress = gap > 0 ? (now - gapStart) / gap : 1
                return .interlude(before: pending, progress: min(max(progress, 0), 1))
            }
        }
        return currentIndex.map(LyricsFocus.line) ?? .none
    }

    /// When line `i`'s content ends: its `end`, else its last word, else — for
    /// line-level lyrics — capped just short of the next line so ordinary gaps
    /// don't register but long silences do.
    private static func contentEnd(of i: Int, in lines: [LyricLine]) -> Double {
        if let end = lines[i].end { return end }
        if let lastWord = lines[i].words.last?.time { return lastWord }
        let nextStart = i + 1 < lines.count ? lines[i + 1].time : .greatestFiniteMagnitude
        return min(lines[i].time + assumedLineDuration, nextStart)
    }
}

/// Where lyrics are fetched from.
nonisolated enum LyricsProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    /// YouTube Music's own lyrics tab (matches the playing track exactly, but
    /// only covers tracks YT Music has lyrics for).
    case youtubeMusic
    /// LRCLIB (lrclib.net) — a free, open lyrics database matched by metadata.
    case lrclib
    /// Musixmatch — matched by metadata; the only source here with word-level
    /// ("richsync") timing, enabling a word-by-word highlight. Uses an
    /// unofficial endpoint, so it can be less reliable than the others.
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

/// Everything a lyrics provider might need to find a track's lyrics. The
/// YouTube Music provider keys off `videoId`; LRCLIB matches on the metadata.
nonisolated struct LyricsQuery: Sendable, Equatable {
    var videoId: String
    var title: String
    var artist: String
    var album: String
    /// Track length in seconds, when known (improves LRCLIB's exact match).
    var duration: Double?
}
