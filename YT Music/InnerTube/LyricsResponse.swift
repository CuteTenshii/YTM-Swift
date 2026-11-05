//
//  LyricsResponse.swift
//  YT Music
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
    /// A track without lyrics carries a messageRenderer instead, so the description is absent and this is nil.
    static func parse(_ response: LyricsResponse) -> Lyrics? {
        let shelf = response.contents?.sectionListRenderer?.contents?
            .compactMap(\.musicDescriptionShelfRenderer).first
        guard let text = shelf?.description?.text, !text.isEmpty else { return nil }
        let source = shelf?.footer?.text
        return Lyrics(text: text, source: (source?.isEmpty ?? true) ? nil : source)
    }
}
