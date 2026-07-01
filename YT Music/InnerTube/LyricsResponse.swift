//
//  LyricsResponse.swift
//  YT Music
//
//  Decodable model for the InnerTube `browse` response of a lyrics page. The
//  lyrics tab's browse id (an `MPLYt…`) is found in the `next` response (see
//  WatchNextParser.lyricsBrowseId); browsing it returns the text here.
//
//  Response path:
//    contents.sectionListRenderer.contents[]
//      .musicDescriptionShelfRenderer
//        .description.runs[].text   <- the lyrics
//        .footer.runs[].text        <- "Source: …"
//
//  When a track has no lyrics the section carries a messageRenderer instead, so
//  the description is absent and the parser yields nil.
//

import Foundation

nonisolated struct LyricsResponse: Decodable {
    let contents: Contents?

    struct Contents: Decodable {
        let sectionListRenderer: SectionList?
    }

    struct SectionList: Decodable {
        let contents: [Section]?
    }

    struct Section: Decodable {
        let musicDescriptionShelfRenderer: DescriptionShelf?
    }

    struct DescriptionShelf: Decodable {
        let description: InnerTubeText?
        let footer: InnerTubeText?
    }
}

nonisolated enum LyricsParser {
    /// Extracts the lyric text (and attribution) from a lyrics browse response,
    /// or nil when the track has no lyrics.
    static func parse(_ response: LyricsResponse) -> Lyrics? {
        let shelf = response.contents?.sectionListRenderer?.contents?
            .compactMap(\.musicDescriptionShelfRenderer).first
        guard let text = shelf?.description?.text, !text.isEmpty else { return nil }
        let source = shelf?.footer?.text
        return Lyrics(text: text, source: (source?.isEmpty ?? true) ? nil : source)
    }
}
