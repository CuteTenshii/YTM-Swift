//
//  MusixmatchRichSync.swift
//  YT Music
//

import Foundation

/// Parses Musixmatch richsync JSON into word-timed `LyricLine`s.
/// Shape: `[{"ts","te","x","l":[{"c","o"}]}]`, `o` being the token offset from `ts`.
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

    static func parse(_ body: String) -> [LyricLine] {
        guard let data = body.data(using: .utf8),
              let segments = try? JSONDecoder().decode([Segment].self, from: data)
        else { return [] }
        return segments.enumerated().map { index, segment in
            let words = (segment.l ?? []).map {
                TimedWord(time: segment.ts + $0.o, text: $0.c)
            }
            let text = segment.x ?? words.map(\.text).joined()
            return LyricLine(time: segment.ts,
                             text: text.trimmingCharacters(in: .whitespaces),
                             id: index,
                             words: words,
                             end: segment.te)
        }
    }
}
