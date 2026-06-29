//
//  WatchNextResponse.swift
//  YT Music
//
//  Decodable models for the InnerTube `next` endpoint, which powers "Start
//  radio": given a seed video it returns an endless queue of related tracks. We
//  only model the keys we consume; all optional.
//
//  Response path:
//    contents.singleColumnMusicWatchNextResultsRenderer
//      .tabbedRenderer.watchNextTabbedResultsRenderer
//      .tabs[0].tabRenderer.content
//      .musicQueueRenderer.content.playlistPanelRenderer.contents[]
//        .playlistPanelVideoRenderer { videoId, title, longBylineText, lengthText, thumbnail }
//

import Foundation

struct WatchNextResponse: Decodable {
    let contents: Contents?

    struct Contents: Decodable {
        let singleColumnMusicWatchNextResultsRenderer: SingleColumn?
    }

    struct SingleColumn: Decodable {
        let tabbedRenderer: TabbedRenderer?
    }

    struct TabbedRenderer: Decodable {
        let watchNextTabbedResultsRenderer: TabbedResults?
    }

    struct TabbedResults: Decodable {
        let tabs: [Tab]?
    }

    struct Tab: Decodable {
        let tabRenderer: TabRenderer?
    }

    struct TabRenderer: Decodable {
        let content: TabContent?
    }

    struct TabContent: Decodable {
        let musicQueueRenderer: MusicQueueRenderer?
    }

    struct MusicQueueRenderer: Decodable {
        let content: QueueContent?
    }

    struct QueueContent: Decodable {
        let playlistPanelRenderer: PlaylistPanelRenderer?
    }

    struct PlaylistPanelRenderer: Decodable {
        let contents: [PanelItem]?
    }

    struct PanelItem: Decodable {
        let playlistPanelVideoRenderer: PanelVideoRenderer?
    }

    struct PanelVideoRenderer: Decodable {
        let videoId: String?
        let title: InnerTubeText?
        let longBylineText: InnerTubeText?
        let lengthText: InnerTubeText?
        let thumbnail: ThumbnailList?

        /// Plain `{ thumbnails: [...] }` (unlike browse, which wraps it in a
        /// musicThumbnailRenderer).
        struct ThumbnailList: Decodable {
            let thumbnails: [Thumbnail]?

            struct Thumbnail: Decodable {
                let url: String
                let width: Int?
                let height: Int?
            }

            var bestURL: URL? {
                (thumbnails ?? [])
                    .max { ($0.width ?? 0) < ($1.width ?? 0) }
                    .flatMap { URL(string: $0.url) }
            }
        }
    }
}

nonisolated enum WatchNextParser {
    /// Flattens the queue's panel into playable Tracks (the seed is first).
    static func parse(_ response: WatchNextResponse) -> [Track] {
        let items = response.contents?
            .singleColumnMusicWatchNextResultsRenderer?
            .tabbedRenderer?.watchNextTabbedResultsRenderer?
            .tabs?.first?.tabRenderer?.content?
            .musicQueueRenderer?.content?.playlistPanelRenderer?.contents ?? []

        var index = 1
        return items.compactMap { item -> Track? in
            guard let video = item.playlistPanelVideoRenderer,
                  let videoId = video.videoId else { return nil }
            defer { index += 1 }
            return Track(
                index: index,
                title: video.title?.text ?? "",
                subtitle: video.longBylineText?.text ?? "",
                duration: video.lengthText?.text,
                thumbnailURL: video.thumbnail?.bestURL,
                videoId: videoId
            )
        }
    }
}
