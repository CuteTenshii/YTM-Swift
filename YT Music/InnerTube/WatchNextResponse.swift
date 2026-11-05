//
//  WatchNextResponse.swift
//  YT Music
//

import Foundation

struct WatchNextResponse: Decodable {
    let contents: Contents?
    // Carries the seed track's like button (account-relative rating).
    let playerOverlays: PlayerOverlays?

    struct Contents: Decodable {
        let singleColumnMusicWatchNextResultsRenderer: SingleColumn?
    }

    // Like state: playerOverlays.playerOverlayRenderer.actions[].likeButtonRenderer
    struct PlayerOverlays: Decodable {
        let playerOverlayRenderer: PlayerOverlayRenderer?
    }

    struct PlayerOverlayRenderer: Decodable {
        let actions: [OverlayAction]?
        let videoActionBar: VideoActionBar?
    }

    // Like count: videoActionBar...segmentedLikeDislikeButtonViewModel.likeCountEntity
    struct VideoActionBar: Decodable {
        let videoActionBarViewModel: ViewModel?

        struct ViewModel: Decodable {
            let buttons: [Button]?
        }

        struct Button: Decodable {
            let buttonViewModel: ButtonViewModel?
        }

        struct ButtonViewModel: Decodable {
            let segmentedLikeDislikeButtonViewModel: Segmented?
        }

        struct Segmented: Decodable {
            let likeCountEntity: LikeCountEntity?
        }

        struct LikeCountEntity: Decodable {
            let likeCountIfIndifferentNumber: String?
        }
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
        let title: String?
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
        /// Present once the ~50-track batch is exhausted; resend its token to `next`. WEB_REMIX returns a full batch upfront.
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

        /// Plain `{ thumbnails: [...] }`, unlike browse's musicThumbnailRenderer wrapper.
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

struct RadioContinuationResponse: Decodable {
    let continuationContents: ContinuationContents?

    struct ContinuationContents: Decodable {
        let playlistPanelContinuation: WatchNextResponse.PlaylistPanelRenderer?
    }
}

nonisolated enum WatchNextParser {
    static func parse(_ response: WatchNextResponse) -> [Track] {
        parse(panel(of: response))
    }

    static func parse(_ response: RadioContinuationResponse) -> [Track] {
        parse(response.continuationContents?.playlistPanelContinuation)
    }

    static func continuationToken(_ response: WatchNextResponse) -> String? {
        continuationToken(panel(of: response))
    }

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

    /// Scoped to `videoId`; defaults to `.indifferent` when absent.
    static func likeStatus(_ response: WatchNextResponse, expecting videoId: String) -> LikeStatus {
        let button = response.playerOverlays?.playerOverlayRenderer?
            .actions?.compactMap(\.likeButtonRenderer)
            .first { $0.target?.videoId == videoId }
        return LikeStatus(innerTube: button?.likeStatus)
    }

    static func likeCount(_ response: WatchNextResponse) -> Int? {
        response.playerOverlays?.playerOverlayRenderer?.videoActionBar?
            .videoActionBarViewModel?.buttons?
            .compactMap { $0.buttonViewModel?.segmentedLikeDislikeButtonViewModel?
                .likeCountEntity?.likeCountIfIndifferentNumber }
            .compactMap { Int($0) }.first
    }

    static func lyricsBrowseId(_ response: WatchNextResponse) -> String? {
        browseId(of: "Lyrics", in: response)
    }

    static func relatedBrowseId(_ response: WatchNextResponse) -> String? {
        browseId(of: "Related", in: response)
    }

    private static func browseId(of title: String, in response: WatchNextResponse) -> String? {
        let tabs = response.contents?
            .singleColumnMusicWatchNextResultsRenderer?
            .tabbedRenderer?.watchNextTabbedResultsRenderer?.tabs ?? []
        return tabs.compactMap(\.tabRenderer)
            .first { $0.title == title }?
            .endpoint?.browseEndpoint?.browseId
    }
}
