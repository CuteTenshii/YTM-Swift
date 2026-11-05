//
//  LRCParser.swift
//  YT Music
//

import Foundation

/// Parses LRC-formatted synced lyrics (`[mm:ss.xx] text`) into timed lines.
nonisolated enum LRCParser {
    /// Multi-timestamp lines expand to one entry each; metadata tags and untimed lines are dropped.
    /// Blank timed lines are kept as breathing room.
    static func parse(_ lrc: String) -> [LyricLine] {
        var out: [(time: Double, text: String)] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            var cursor = line.startIndex
            var stamps: [Double] = []
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

    private static func timestamp(_ body: String) -> Double? {
        let parts = body.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }
}
