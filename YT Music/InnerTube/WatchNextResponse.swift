//
//  WatchNextResponse.swift
//  YT Music
//
//  Decodable models for the InnerTube `next` endpoint, which powers "Start
//  radio": given a seed video it returns a batch (~50) of related tracks plus
//  a continuation token to fetch the next batch of the same mix. We only
//  model the keys we consume; all optional.
//
//  Response path:
//    contents.singleColumnMusicWatchNextResultsRenderer
//      .tabbedRenderer.watchNextTabbedResultsRenderer
//      .tabs[0].tabRenderer.content
//      .musicQueueRenderer.content.playlistPanelRenderer
//        .contents[].playlistPanelVideoRenderer { videoId, title, longBylineText, lengthText, thumbnail }
//        .continuations[0].nextRadioContinuationData.continuation
//  A follow-up `next` call with `{"continuation": <token>}` in the body
//  returns the same panel shape at `continuationContents.playlistPanelContinuation`.
//

import Foundation

struct WatchNextResponse: Decodable {
    let contents: Contents?
    /// Carries the seed track's like button (account-relative rating).
    let playerOverlays: PlayerOverlays?

    struct Contents: Decodable {
        let singleColumnMusicWatchNextResultsRenderer: SingleColumn?
    }

    // Like state lives at
    //   playerOverlays.playerOverlayRenderer.actions[].likeButtonRenderer
    //     { likeStatus: LIKE | DISLIKE | INDIFFERENT, target: { videoId } }
    struct PlayerOverlays: Decodable {
        let playerOverlayRenderer: PlayerOverlayRenderer?
    }

    struct PlayerOverlayRenderer: Decodable {
        let actions: [OverlayAction]?
    }

    struct OverlayAction: Decodable {
        let likeButtonRenderer: LikeButtonRenderer?
    }

    struct LikeButtonRenderer: Decodable {
        let likeStatus: String?
        let target: LikeTarget?

        struct LikeTarget: Decodable {
            let videoId: String?
        }
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
        /// Tab label ("Up next", "Lyrics", "Related").
        let title: String?
        /// The browse endpoint a non-content tab (Lyrics/Related) points at.
        let endpoint: NavigationEndpoint?
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
        /// Present once the panel's ~50-track batch is exhausted; its token,
        /// resent as `{"continuation": …}` to `next`, fetches the mix's next
        /// batch (see `RadioContinuationResponse`). Verified against the live
        /// endpoint: WEB_REMIX returns a full batch upfront, not the smaller
        /// per-call pages yt-dlp's classic-YouTube mix pagination assumes.
        let continuations: [Continuation]?
    }

    struct Continuation: Decodable {
        let nextRadioContinuationData: ContinuationData?
    }

    struct ContinuationData: Decodable {
        let continuation: String?
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

/// A follow-up `next` response fetched by resending a `playlistPanelRenderer`
/// continuation token — shares the same panel-item shape as the initial
/// `WatchNextResponse`, just nested under `continuationContents` instead of
/// the full watch-next tab layout.
struct RadioContinuationResponse: Decodable {
    let continuationContents: ContinuationContents?

    struct ContinuationContents: Decodable {
        let playlistPanelContinuation: WatchNextResponse.PlaylistPanelRenderer?
    }
}

nonisolated enum WatchNextParser {
    /// Flattens the queue's panel into playable Tracks (the seed is first).
    static func parse(_ response: WatchNextResponse) -> [Track] {
        parse(panel(of: response))
    }

    /// Flattens a continuation batch into playable Tracks.
    static func parse(_ response: RadioContinuationResponse) -> [Track] {
        parse(response.continuationContents?.playlistPanelContinuation)
    }

    /// The token to fetch the mix's next batch, if the current one isn't the
    /// last (see `PlaylistPanelRenderer.continuations`).
    static func continuationToken(_ response: WatchNextResponse) -> String? {
        continuationToken(panel(of: response))
    }

    /// The token to fetch yet another batch beyond this continuation, if any.
    static func continuationToken(_ response: RadioContinuationResponse) -> String? {
        continuationToken(response.continuationContents?.playlistPanelContinuation)
    }

    private static func panel(of response: WatchNextResponse) -> WatchNextResponse.PlaylistPanelRenderer? {
        response.contents?
            .singleColumnMusicWatchNextResultsRenderer?
            .tabbedRenderer?.watchNextTabbedResultsRenderer?
            .tabs?.first?.tabRenderer?.content?
            .musicQueueRenderer?.content?.playlistPanelRenderer
    }

    private static func parse(_ panel: WatchNextResponse.PlaylistPanelRenderer?) -> [Track] {
        var index = 1
        return (panel?.contents ?? []).compactMap { item -> Track? in
            guard let video = item.playlistPanelVideoRenderer,
                  let videoId = video.videoId else { return nil }
            defer { index += 1 }
            let links = video.longBylineText?.entityLinks ?? []
            return Track(
                index: index,
                title: video.title?.text ?? "",
                subtitle: video.longBylineText?.text ?? "",
                duration: video.lengthText?.text,
                thumbnailURL: video.thumbnail?.bestURL,
                videoId: videoId,
                artists: links.filter { $0.kind == .artist },
                albumLink: links.first { $0.kind == .album }
            )
        }
    }

    private static func continuationToken(_ panel: WatchNextResponse.PlaylistPanelRenderer?) -> String? {
        panel?.continuations?.first?.nextRadioContinuationData?.continuation
    }

    /// The seed track's like rating from the watch-next overlay, scoped to the
    /// expected `videoId` so a mismatched response doesn't mislabel the track.
    /// Defaults to `.indifferent` when absent (e.g. signed out, or likes not
    /// allowed for the video).
    static func likeStatus(_ response: WatchNextResponse, expecting videoId: String) -> LikeStatus {
        let button = response.playerOverlays?.playerOverlayRenderer?
            .actions?.compactMap(\.likeButtonRenderer)
            .first { $0.target?.videoId == videoId }
        return LikeStatus(innerTube: button?.likeStatus)
    }

    /// The browse id of the watch-next "Lyrics" tab, if the track has lyrics.
    /// Fed to a follow-up `browse` call to fetch the lyric text. nil when the
    /// track exposes no lyrics tab.
    static func lyricsBrowseId(_ response: WatchNextResponse) -> String? {
        browseId(of: "Lyrics", in: response)
    }

    /// The browse id of the watch-next "Related" tab. Fed to a follow-up `browse`
    /// call to fetch the track's related-music shelves (similar songs, artists,
    /// recommended playlists). nil when the track exposes no related tab.
    static func relatedBrowseId(_ response: WatchNextResponse) -> String? {
        browseId(of: "Related", in: response)
    }

    /// The browse id of the watch-next tab with the given title, if present.
    private static func browseId(of title: String, in response: WatchNextResponse) -> String? {
        let tabs = response.contents?
            .singleColumnMusicWatchNextResultsRenderer?
            .tabbedRenderer?.watchNextTabbedResultsRenderer?.tabs ?? []
        return tabs.compactMap(\.tabRenderer)
            .first { $0.title == title }?
            .endpoint?.browseEndpoint?.browseId
    }
}
