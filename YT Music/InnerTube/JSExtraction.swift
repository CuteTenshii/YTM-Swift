//
//  JSExtraction.swift
//  YT Music
//
//  Text-processing helpers for pulling data out of YouTube's minified base.js.
//  These are `nonisolated` so the `SignatureDecipher` actor can call them
//  synchronously.
//

import Foundation

extension SignatureDecipher {

    // MARK: - Regex

    /// First capture group of the first match, or nil.
    nonisolated func firstMatch(in text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        ) else { return nil }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > group,
              let captured = Range(match.range(at: group), in: text) else {
            return nil
        }
        return String(text[captured])
    }

    /// The capture group `group` of every match, in order.
    nonisolated func allMatches(in text: String, pattern: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        ) else { return [] }

        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > group,
                  let captured = Range(match.range(at: group), in: text) else { return nil }
            return String(text[captured])
        }
    }
}
