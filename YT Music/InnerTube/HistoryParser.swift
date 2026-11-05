//
//  HistoryParser.swift
//  YT Music
//
//

import Foundation

nonisolated enum HistoryParser {

    static func parse(_ response: BrowseResponse) -> [HistorySection] {
        let sections = response.contents?
            .singleColumnBrowseResultsRenderer?
            .tabs?.first?
            .tabRenderer?.content?
            .sectionListRenderer?.contents ?? []

        return sections.compactMap { section in
            guard let shelf = section.listShelf else { return nil }
            let tracks = parseTracks(shelf)
            guard !tracks.isEmpty else { return nil }
            return HistorySection(title: shelf.title?.text ?? "History", tracks: tracks)
        }
    }

    private static func parseTracks(_ shelf: MusicShelfRenderer) -> [Track] {
        var index = 1
        return (shelf.contents ?? []).compactMap { item in
            guard let row = item.musicResponsiveListItemRenderer else { return nil }
            let columns = row.textColumns
            guard let title = columns.first else { return nil }

            defer { index += 1 }
            let links = row.entityLinks
            return Track(
                index: index,
                title: title,
                subtitle: columns.dropFirst().joined(separator: " • "),
                duration: row.durationText,
                thumbnailURL: row.thumbnail?.bestURL,
                videoId: row.trackVideoId,
                artists: links.filter { $0.kind == .artist },
                albumLink: links.first { $0.kind == .album },
                feedbackToken: row.feedbackToken,
                likeStatus: row.likeStatus ?? .indifferent
            )
        }
    }
}
