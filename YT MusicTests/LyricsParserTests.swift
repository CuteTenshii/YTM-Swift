//
//  LyricsParserTests.swift
//  YT MusicTests
//
//  Verifies the lyrics browse decode + parse, and the watch-next lyrics-tab
//  browse-id extraction, against fixtures shaped like the real responses.
//

import Testing
import Foundation
@testable import YT_Music

@Suite("Lyrics parser")
struct LyricsParserTests {

    private let fixture = """
    {"contents":{"sectionListRenderer":{"contents":[
    {"musicDescriptionShelfRenderer":{
    "description":{"runs":[{"text":"Line one\\nLine two"}]},
    "footer":{"runs":[{"text":"Source: Musixmatch"}]}}}
    ]}}}
    """

    @Test("Extracts lyric text and the source attribution")
    func parsesLyrics() throws {
        let response = try JSONDecoder().decode(LyricsResponse.self, from: Data(fixture.utf8))
        let lyrics = try #require(LyricsParser.parse(response))
        #expect(lyrics.text == "Line one\nLine two")
        #expect(lyrics.source == "Source: Musixmatch")
    }

    @Test("A response with no description yields nil (track has no lyrics)")
    func nilWhenAbsent() throws {
        let empty = try JSONDecoder().decode(LyricsResponse.self, from: Data("{}".utf8))
        #expect(LyricsParser.parse(empty) == nil)

        // A "message" section (the not-available case) carries no description.
        let message = """
        {"contents":{"sectionListRenderer":{"contents":[{"messageRenderer":{}}]}}}
        """
        let response = try JSONDecoder().decode(LyricsResponse.self, from: Data(message.utf8))
        #expect(LyricsParser.parse(response) == nil)
    }

    // The lyrics tab in a `next` response carries the MPLYt browse id.
    private let tabsFixture = """
    {"contents":{"singleColumnMusicWatchNextResultsRenderer":{"tabbedRenderer":
    {"watchNextTabbedResultsRenderer":{"tabs":[
    {"tabRenderer":{"title":"Up next","content":{"musicQueueRenderer":{}}}},
    {"tabRenderer":{"title":"Lyrics","endpoint":{"browseEndpoint":{"browseId":"MPLYt_abc"}}}},
    {"tabRenderer":{"title":"Related","endpoint":{"browseEndpoint":{"browseId":"MPTRt_xyz"}}}}
    ]}}}}}
    """

    @Test("Finds the lyrics tab's browse id by title")
    func findsLyricsBrowseId() throws {
        let response = try JSONDecoder().decode(WatchNextResponse.self, from: Data(tabsFixture.utf8))
        #expect(WatchNextParser.lyricsBrowseId(response) == "MPLYt_abc")
    }

    @Test("No lyrics tab → nil browse id")
    func noLyricsTab() throws {
        let response = try JSONDecoder().decode(WatchNextResponse.self, from: Data("{}".utf8))
        #expect(WatchNextParser.lyricsBrowseId(response) == nil)
    }
}

@Suite("LRC synced-lyrics parser")
struct LRCParserTests {

    @Test("Parses timestamps to seconds, sorted, with stable ids")
    func parsesTimedLines() {
        let lrc = """
        [00:12.50]First line
        [00:15.00]Second line
        [01:03.20]Third line
        """
        let lines = LRCParser.parse(lrc)
        #expect(lines.map(\.text) == ["First line", "Second line", "Third line"])
        #expect(lines.map(\.time) == [12.5, 15.0, 63.2])
        #expect(lines.map(\.id) == [0, 1, 2])
    }

    @Test("Skips metadata tags but keeps their timed line text")
    func skipsMetadata() {
        let lrc = """
        [ar:Some Artist]
        [ti:Some Title]
        [00:01.00]Only real line
        """
        let lines = LRCParser.parse(lrc)
        #expect(lines.count == 1)
        #expect(lines.first?.text == "Only real line")
        #expect(lines.first?.time == 1.0)
    }

    @Test("A line with multiple timestamps expands to one entry each, time-sorted")
    func expandsRepeatedTimestamps() {
        let lrc = "[00:10.00][01:00.00]Chorus\n[00:30.00]Verse"
        let lines = LRCParser.parse(lrc)
        #expect(lines.map(\.time) == [10.0, 30.0, 60.0])
        #expect(lines.map(\.text) == ["Chorus", "Verse", "Chorus"])
    }

    @Test("Keeps blank timed lines (breathing room)")
    func keepsBlankTimedLines() {
        let lines = LRCParser.parse("[00:05.00]\n[00:07.00]Sing")
        #expect(lines.count == 2)
        #expect(lines.first?.text == "")
    }

    @Test("Plain text with no timestamps yields no synced lines")
    func plainTextYieldsNothing() {
        #expect(LRCParser.parse("Just some\nplain lyrics").isEmpty)
    }
}

@Suite("Synced-lyrics focus")
struct LyricsFocusTests {

    private func lines(_ times: [Double]) -> [LyricLine] {
        times.enumerated().map { LyricLine(time: $1, text: "l\($0)", id: $0) }
    }

    @Test("Empty lyrics focus on nothing")
    func emptyIsNone() {
        #expect(LyricsFocus.resolve([], at: 5) == .none)
    }

    @Test("Before the first line (short intro) nothing is highlighted")
    func beforeFirstShortIntro() {
        #expect(LyricsFocus.resolve(lines([2, 4, 6]), at: 1) == .none)
    }

    @Test("The active line is the last one whose time has passed")
    func activeLineIsLastPassed() {
        let ls = lines([0, 5, 10])
        #expect(LyricsFocus.resolve(ls, at: 6) == .line(1))
        #expect(LyricsFocus.resolve(ls, at: 10) == .line(2))
        #expect(LyricsFocus.resolve(ls, at: 100) == .line(2))
    }

    @Test("A word-timed line stays active (sweeping) until its words end")
    func wordTimedLineStaysActive() {
        // Line 0 sung 10→17 (last word at 16, end 17); next line at 19.
        let ls = [
            LyricLine(time: 10, text: "a b", id: 0,
                      words: [TimedWord(time: 10, text: "a "), TimedWord(time: 16, text: "b")],
                      end: 17),
            LyricLine(time: 19, text: "c", id: 1),
        ]
        // Mid-line: still line 0, so the word sweep keeps running (not dots).
        #expect(LyricsFocus.resolve(ls, at: 14) == .line(0))
        // Short 2s tail gap (17→19) is under threshold → no interlude.
        #expect(LyricsFocus.resolve(ls, at: 18) == .line(0))
    }

    @Test("A long silence after a line's content becomes an interlude")
    func longTailIsInterlude() {
        // Line 0 ends at 15; next line at 25 → a 10s instrumental gap.
        let ls = [
            LyricLine(time: 10, text: "a", id: 0, words: [TimedWord(time: 10, text: "a")], end: 15),
            LyricLine(time: 25, text: "b", id: 1),
        ]
        #expect(LyricsFocus.resolve(ls, at: 14) == .line(0))   // content still going
        guard case .interlude(let before, let progress) = LyricsFocus.resolve(ls, at: 20) else {
            return #expect(Bool(false))
        }
        #expect(before == 1)
        #expect(abs(progress - 0.5) < 0.001)   // 5s into the 10s gap (15→25)
    }

    @Test("Ordinary line-level gaps don't trigger an interlude")
    func shortLineLevelGapNoInterlude() {
        // 4s between line starts, no word/end info → line stays active.
        #expect(LyricsFocus.resolve(lines([0, 4, 8]), at: 3) == .line(0))
    }

    @Test("A long intro before the first line shows interlude dots")
    func longIntroIsInterlude() {
        let ls = lines([10, 15])   // 10s intro (≥ threshold)
        guard case .interlude(let before, _) = LyricsFocus.resolve(ls, at: 7) else {
            return #expect(Bool(false))
        }
        #expect(before == 0)
    }
}

@Suite("Musixmatch richsync parser")
struct MusixmatchRichSyncTests {

    @Test("Parses word-level timings (offset added to line start)")
    func parsesWords() {
        let body = """
        [{"ts":10.0,"te":13.0,"x":"Hello world","l":[{"c":"Hello ","o":0.0},{"c":"world","o":1.5}]},
         {"ts":13.0,"te":15.0,"x":"Again","l":[{"c":"Again","o":0.2}]}]
        """
        let lines = MusixmatchRichSync.parse(body)
        #expect(lines.count == 2)
        #expect(lines[0].text == "Hello world")
        #expect(lines[0].time == 10.0)
        #expect(lines[0].words.map(\.text) == ["Hello ", "world"])
        #expect(lines[0].words.map(\.time) == [10.0, 11.5])   // ts + offset
        #expect(lines[0].end == 13.0)                          // te
        #expect(lines[1].words.first?.time == 13.2)
        #expect(lines.map(\.id) == [0, 1])
    }

    @Test("Rebuilds line text from tokens when x is absent")
    func rebuildsFromTokens() {
        let body = #"[{"ts":1.0,"l":[{"c":"na ","o":0.0},{"c":"na","o":0.5}]}]"#
        let lines = MusixmatchRichSync.parse(body)
        #expect(lines.first?.text == "na na")
    }

    @Test("Invalid JSON yields no lines")
    func invalidJSON() {
        #expect(MusixmatchRichSync.parse("not json").isEmpty)
        #expect(MusixmatchRichSync.parse("").isEmpty)
    }
}
