//
//  JSExtraction.swift
//  YT Music
//
//  Pure text-processing helpers for pulling specific function / object / array
//  literals out of YouTube's minified base.js. These are `nonisolated` so the
//  `SignatureDecipher` actor can call them synchronously.
//
//  The brace matcher is string-literal aware (skips `"`, `'`, `` ` ``) but does
//  not special-case regex literals — a known limitation if a target function
//  embeds a regex containing unbalanced braces.
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

    /// Range of the whole first match, or nil.
    private nonisolated func matchRange(in text: String, pattern: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        ) else { return nil }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let result = Range(match.range, in: text) else {
            return nil
        }
        return result
    }

    // MARK: - Literal extraction

    /// Returns the full `function(...){...}` text for a function defined as
    /// `name = function`, `name: function`, or `function name(...)`.
    nonisolated func functionLiteral(named name: String, in js: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            #"\b\#(escaped)\s*=\s*function\b"#,
            #"\b\#(escaped)\s*:\s*function\b"#,
            #"\bfunction\s+\#(escaped)\b"#,
        ]

        for pattern in patterns {
            guard let header = matchRange(in: js, pattern: pattern),
                  let functionKeyword = js.range(of: "function", range: header),
                  let bodyOpen = js[header.upperBound...].firstIndex(of: "{"),
                  let body = balancedRange(in: js, from: bodyOpen, open: "{", close: "}") else {
                continue
            }
            return String(js[functionKeyword.lowerBound..<body.upperBound])
        }
        return nil
    }

    /// Returns the `{...}` object literal assigned to `name`.
    nonisolated func objectLiteral(named name: String, in js: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?:var\s+)?\b\#(escaped)\s*=\s*\{"#

        guard let header = matchRange(in: js, pattern: pattern),
              let open = js[header.lowerBound...].firstIndex(of: "{"),
              let body = balancedRange(in: js, from: open, open: "{", close: "}") else {
            return nil
        }
        return String(js[open..<body.upperBound])
    }

    /// Returns element `index` of the array literal assigned to `name`
    /// (used to resolve `n`-function names hidden behind an array indirection).
    nonisolated func arrayElement(named name: String, index: Int, in js: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?:var\s+)?\b\#(escaped)\s*=\s*\["#

        guard let header = matchRange(in: js, pattern: pattern),
              let open = js[header.lowerBound...].firstIndex(of: "["),
              let body = balancedRange(in: js, from: open, open: "[", close: "]") else {
            return nil
        }
        let innerStart = js.index(after: open)
        let innerEnd = js.index(before: body.upperBound)
        let elements = splitTopLevel(String(js[innerStart..<innerEnd]))
        guard index >= 0, index < elements.count else { return nil }
        return elements[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns a re-declarable `var name=<value>;` for a top-level definition
    /// (`name=…;` or `var name=…;`), with `<value>` captured up to the matching
    /// statement-terminating `;` (respecting nested ()/[]/{} and strings). Used to
    /// pull in globals that an `nsig` function references but doesn't contain.
    nonisolated func topLevelDefinition(named name: String, in js: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?:^|[;\n,{}])\s*(?:var\s+)?\#(escaped)\s*="#

        guard let header = matchRange(in: js, pattern: pattern) else { return nil }

        var index = header.upperBound        // first char of the value
        let start = index
        var depth = 0
        var stringDelimiter: Character?
        var escapedChar = false

        while index < js.endIndex {
            let c = js[index]
            if let delimiter = stringDelimiter {
                if escapedChar { escapedChar = false }
                else if c == "\\" { escapedChar = true }
                else if c == delimiter { stringDelimiter = nil }
            } else {
                switch c {
                case "\"", "'", "`": stringDelimiter = c
                case "(", "[", "{": depth += 1
                case ")", "]", "}": depth -= 1
                case ";" where depth == 0:
                    return "var \(name)=\(js[start..<index]);"
                default: break
                }
            }
            index = js.index(after: index)
        }
        return nil
    }

    // MARK: - Scanning

    /// Range from an opening delimiter to (and including) its matching close,
    /// skipping delimiters that appear inside string literals.
    private nonisolated func balancedRange(
        in s: String,
        from openIndex: String.Index,
        open: Character,
        close: Character
    ) -> Range<String.Index>? {
        var depth = 0
        var i = openIndex
        var stringDelimiter: Character?
        var escaped = false

        while i < s.endIndex {
            let c = s[i]
            if let delimiter = stringDelimiter {
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == delimiter {
                    stringDelimiter = nil
                }
            } else {
                switch c {
                case "\"", "'", "`":
                    stringDelimiter = c
                case open:
                    depth += 1
                case close:
                    depth -= 1
                    if depth == 0 {
                        return openIndex..<s.index(after: i)
                    }
                default:
                    break
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    /// Splits a comma-separated list, ignoring commas nested in brackets/strings.
    private nonisolated func splitTopLevel(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var stringDelimiter: Character?
        var escaped = false

        for c in s {
            if let delimiter = stringDelimiter {
                current.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == delimiter { stringDelimiter = nil }
                continue
            }
            switch c {
            case "\"", "'", "`":
                stringDelimiter = c
                current.append(c)
            case "(", "[", "{":
                depth += 1
                current.append(c)
            case ")", "]", "}":
                depth -= 1
                current.append(c)
            case "," where depth == 0:
                parts.append(current)
                current = ""
            default:
                current.append(c)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}
