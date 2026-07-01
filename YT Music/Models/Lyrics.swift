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
        let currentIndex: Int? = if let pending { pending == 0 ? nil : pending - 1 }
                                 else { lines.count - 1 }

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

/// Parses LRC-formatted synced lyrics (`[mm:ss.xx] text`) into timed lines.
nonisolated enum LRCParser {
    /// Turns an LRC document into time-sorted `LyricLine`s. A line may carry
    /// several timestamps (a shared chorus); each expands to its own entry.
    /// Metadata tags (`[ar:…]`, `[ti:…]`, …) and untimed lines are dropped.
    /// Blank timed lines are kept (they render as breathing room). Returns an
    /// empty array when nothing timed is found.
    static func parse(_ lrc: String) -> [LyricLine] {
        var out: [(time: Double, text: String)] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            var cursor = line.startIndex
            var stamps: [Double] = []
            // Consume any leading `[…]` tags; keep the numeric timestamps.
            while cursor < line.endIndex, line[cursor] == "[",
                  let close = line[cursor...].firstIndex(of: "]") {
                let inner = String(line[line.index(after: cursor)..<close])
                if let seconds = timestamp(inner) { stamps.append(seconds) }
                cursor = line.index(after: close)
            }
            guard !stamps.isEmpty else { continue }
            let text = String(line[cursor...]).trimmingCharacters(in: .whitespaces)
            for stamp in stamps { out.append((stamp, text)) }
        }
        return out.sorted { $0.time < $1.time }
            .enumerated()
            .map { LyricLine(time: $0.element.time, text: $0.element.text, id: $0.offset) }
    }

    /// Parses an LRC timestamp body (`mm:ss`, `mm:ss.xx`, `mm:ss.xxx`) into
    /// seconds, or nil for a non-timestamp tag (e.g. `ar:Artist`).
    private static func timestamp(_ body: String) -> Double? {
        let parts = body.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }
}

/// Parses Musixmatch's "richsync" body — a JSON string of word-timed lines —
/// into `LyricLine`s carrying per-word timings.
///
/// The body is a JSON array of segments:
///   `[{"ts":10.5,"te":14.0,"x":"Full line","l":[{"c":"Full ","o":0.0}, …]}, …]`
/// where `ts`/`te` are the line's start/end (seconds), `x` is the full line
/// text, and each `l` entry is a token `c` with an offset `o` from `ts`.
nonisolated enum MusixmatchRichSync {
    private struct Segment: Decodable {
        let ts: Double
        let te: Double?
        let x: String?
        let l: [Token]?
    }
    private struct Token: Decodable {
        let c: String
        let o: Double
    }

    /// Decodes the richsync body string into word-timed lines, or an empty
    /// array when it isn't valid richsync JSON.
    static func parse(_ body: String) -> [LyricLine] {
        guard let data = body.data(using: .utf8),
              let segments = try? JSONDecoder().decode([Segment].self, from: data)
        else { return [] }
        return segments.enumerated().map { index, segment in
            let words = (segment.l ?? []).map {
                TimedWord(time: segment.ts + $0.o, text: $0.c)
            }
            // Prefer the explicit line text; else rebuild it from the tokens.
            let text = segment.x ?? words.map(\.text).joined()
            return LyricLine(time: segment.ts,
                             text: text.trimmingCharacters(in: .whitespaces),
                             id: index,
                             words: words,
                             end: segment.te)
        }
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

