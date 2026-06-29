//
//  BrowseResponse.swift
//  YT Music
//
//  Decodable models mirroring the (deeply nested, polymorphic) JSON returned by
//  the InnerTube `browse` endpoint. We only model the keys we actually consume;
//  everything is optional because YouTube's renderers are wildly inconsistent.
//
//  Response path for the home feed:
//    contents
//      .singleColumnBrowseResultsRenderer
//      .tabs[0].tabRenderer.content
//      .sectionListRenderer.contents[]            <- array of shelves
//        .musicCarouselShelfRenderer
//          .header.musicCarouselShelfBasicHeaderRenderer.title.runs[].text
//          .contents[]                            <- array of cards
//            .musicTwoRowItemRenderer / .musicResponsiveListItemRenderer
//

import Foundation

// MARK: - Top level

struct BrowseResponse: Decodable {
    let contents: Contents?

    struct Contents: Decodable {
        let singleColumnBrowseResultsRenderer: SingleColumn?
    }

    struct SingleColumn: Decodable {
        let tabs: [Tab]?
    }

    struct Tab: Decodable {
        let tabRenderer: TabRenderer?
    }

    struct TabRenderer: Decodable {
        let content: TabContent?
    }

    struct TabContent: Decodable {
        let sectionListRenderer: SectionList?
    }

    struct SectionList: Decodable {
        let contents: [SectionContent]?
    }

    /// A single entry in a section list. Home shelves arrive as carousels;
    /// album/playlist/artist pages also use `musicShelfRenderer` (a track list)
    /// and `musicPlaylistShelfRenderer`; the Library uses `gridRenderer`.
    ///
    /// Modeled as a `final class` (reference type): this node aggregates several
    /// large renderer structs, and copying it by value tripped a value-witness
    /// miscompile in the current toolchain.
    nonisolated final class SectionContent: Decodable, @unchecked Sendable {
        let musicCarouselShelfRenderer: MusicCarouselShelfRenderer?
        let musicImmersiveCarouselShelfRenderer: MusicCarouselShelfRenderer?
        let musicShelfRenderer: MusicShelfRenderer?
        let musicPlaylistShelfRenderer: MusicShelfRenderer?
        let gridRenderer: GridRenderer?

        var carousel: MusicCarouselShelfRenderer? {
            musicCarouselShelfRenderer ?? musicImmersiveCarouselShelfRenderer
        }

        /// A flat track-list shelf (album / playlist tracks, artist top songs).
        var listShelf: MusicShelfRenderer? {
            musicShelfRenderer ?? musicPlaylistShelfRenderer
        }
    }
}

/// A wrapping grid of cards. Used by the Library landing page.
nonisolated struct GridRenderer: Decodable {
    let header: GridHeader?
    let items: [CarouselItem]?

    struct GridHeader: Decodable {
        let gridHeaderRenderer: Inner?
        struct Inner: Decodable { let title: InnerTubeText? }
    }

    var title: String { header?.gridHeaderRenderer?.title?.text ?? "" }
}

/// A flat list shelf whose `contents` are list rows. Used for track listings.
struct MusicShelfRenderer: Decodable {
    let title: InnerTubeText?
    let contents: [CarouselItem]?
}

// MARK: - Carousel shelf

nonisolated struct MusicCarouselShelfRenderer: Decodable {
    let header: Header?
    let contents: [CarouselItem]?

    struct Header: Decodable {
        let musicCarouselShelfBasicHeaderRenderer: Basic?

        struct Basic: Decodable {
            let title: InnerTubeText?
        }
    }

    var title: String {
        header?.musicCarouselShelfBasicHeaderRenderer?.title?.text ?? ""
    }
}

struct CarouselItem: Decodable {
    let musicTwoRowItemRenderer: MusicTwoRowItemRenderer?
    let musicResponsiveListItemRenderer: MusicResponsiveListItemRenderer?
}

// MARK: - Card renderers

/// The big square/circle cards used across most home shelves.
struct MusicTwoRowItemRenderer: Decodable {
    let title: InnerTubeText?
    let subtitle: InnerTubeText?
    let thumbnailRenderer: ThumbnailRendererWrapper?
    let navigationEndpoint: NavigationEndpoint?
}

/// The compact list rows used in shelves like "Quick picks" and in album /
/// playlist track listings.
nonisolated struct MusicResponsiveListItemRenderer: Decodable {
    let flexColumns: [FlexColumn]?
    let fixedColumns: [FixedColumn]?
    let thumbnail: ThumbnailRendererWrapper?
    let navigationEndpoint: NavigationEndpoint?
    let overlay: Overlay?
    let playlistItemData: PlaylistItemData?

    struct FlexColumn: Decodable {
        let musicResponsiveListItemFlexColumnRenderer: FlexRenderer?

        struct FlexRenderer: Decodable {
            let text: InnerTubeText?
        }
    }

    /// Fixed columns hold the track duration ("3:45").
    struct FixedColumn: Decodable {
        let musicResponsiveListItemFixedColumnRenderer: FixedRenderer?

        struct FixedRenderer: Decodable {
            let text: InnerTubeText?
        }
    }

    struct PlaylistItemData: Decodable {
        let videoId: String?
    }

    /// The play button overlay carries the watch endpoint for these rows.
    struct Overlay: Decodable {
        let musicItemThumbnailOverlayRenderer: ThumbnailOverlay?

        struct ThumbnailOverlay: Decodable {
            let content: OverlayContent?

            struct OverlayContent: Decodable {
                let musicPlayButtonRenderer: PlayButton?

                struct PlayButton: Decodable {
                    let playNavigationEndpoint: NavigationEndpoint?
                }
            }
        }
    }

    /// Flattened, non-empty text columns (title first, then artist/subtitle).
    var textColumns: [String] {
        (flexColumns ?? [])
            .compactMap { $0.musicResponsiveListItemFlexColumnRenderer?.text?.text }
            .filter { !$0.isEmpty }
    }

    /// Track duration string, if present ("3:45").
    var durationText: String? {
        (fixedColumns ?? [])
            .compactMap { $0.musicResponsiveListItemFixedColumnRenderer?.text?.text }
            .first { !$0.isEmpty }
    }

    var playEndpoint: NavigationEndpoint? {
        navigationEndpoint
            ?? overlay?.musicItemThumbnailOverlayRenderer?
                .content?.musicPlayButtonRenderer?.playNavigationEndpoint
    }

    /// Most reliable video id for a track row.
    var trackVideoId: String? {
        playlistItemData?.videoId ?? playEndpoint?.watchEndpoint?.videoId
    }
}

// MARK: - Shared primitives

/// YouTube wraps almost all display text in `{ "runs": [{ "text": ... }] }`.
nonisolated struct InnerTubeText: Decodable {
    let runs: [Run]?

    struct Run: Decodable {
        let text: String
        let navigationEndpoint: NavigationEndpoint?
    }

    var text: String {
        (runs ?? []).map(\.text).joined()
    }
}

nonisolated struct ThumbnailRendererWrapper: Decodable {
    let musicThumbnailRenderer: MusicThumbnailRenderer?

    nonisolated struct MusicThumbnailRenderer: Decodable {
        let thumbnail: ThumbnailList?

        struct ThumbnailList: Decodable {
            let thumbnails: [Thumbnail]?
        }

        struct Thumbnail: Decodable {
            let url: String
            let width: Int?
            let height: Int?
        }

        /// Highest-resolution thumbnail URL available.
        var bestURL: URL? {
            let thumbs = thumbnail?.thumbnails ?? []
            let best = thumbs.max { ($0.width ?? 0) < ($1.width ?? 0) }
            return best.flatMap { URL(string: $0.url) }
        }
    }

    /// Highest-resolution thumbnail URL available.
    var bestURL: URL? {
        musicThumbnailRenderer?.bestURL
    }
}

struct NavigationEndpoint: Decodable {
    let watchEndpoint: WatchEndpoint?
    let browseEndpoint: BrowseEndpoint?

    struct WatchEndpoint: Decodable {
        let videoId: String?
        let playlistId: String?
    }

    nonisolated struct BrowseEndpoint: Decodable {
        let browseId: String?
        let browseEndpointContextSupportedConfigs: Configs?

        struct Configs: Decodable {
            let browseEndpointContextMusicConfig: MusicConfig?

            struct MusicConfig: Decodable {
                let pageType: String?   // e.g. MUSIC_PAGE_TYPE_ALBUM / _ARTIST / _PLAYLIST
            }
        }

        var pageType: String? {
            browseEndpointContextSupportedConfigs?
                .browseEndpointContextMusicConfig?.pageType
        }
    }
}
