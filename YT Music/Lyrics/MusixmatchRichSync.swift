//
//  MusixmatchRichSync.swift
//  YT Music
//
//  Decodes Musixmatch richsync JSON into per-word timed lines.
//

import Foundation

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
