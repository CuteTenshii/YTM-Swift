//
//  JSExtraction.swift
//  YT Music
//

import Foundation

extension SignatureDecipher {

    // MARK: - Regex

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
