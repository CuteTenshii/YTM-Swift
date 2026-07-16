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
        let twoColumnBrowseResultsRenderer: TwoColumn?
    }

    /// Newer auth-gated pages (and artist pages) return a two-column layout: the
    /// primary column under `tabs`, plus a `secondaryContents` section list.
    struct TwoColumn: Decodable {
        let tabs: [Tab]?
        let secondaryContents: Secondary?

        struct Secondary: Decodable {
            let sectionListRenderer: SectionList?
        }
    }

    struct SingleColumn: Decodable {
        let tabs: [Tab]?
    }

    struct Tab: Decodable {
        let tabRenderer: TabRenderer?
    }

    struct TabRenderer: Decodable {
        let content: TabContent?
        /// Whether this is the tab the page opens on. The uploads landing page
        /// returns several tabs (Library / Downloads / Uploads) but only the
        /// selected one carries content; the rest are lazy `continuations`.
        let selected: Bool?
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
        let itemSectionRenderer: ItemSectionRenderer?
        let musicCardShelfRenderer: MusicCardShelfRenderer?
        // Real (non-uploaded) albums/playlists put their header inside the body's
        // section list rather than the top-level `header` key.
        let musicResponsiveHeaderRenderer: EntityBrowseResponse.HeaderContainer.ResponsiveHeader?

        var carousel: MusicCarouselShelfRenderer? {
            musicCarouselShelfRenderer ?? musicImmersiveCarouselShelfRenderer
        }

        /// A flat track-list shelf (album / playlist tracks, artist top songs).
        var listShelf: MusicShelfRenderer? {
            musicShelfRenderer ?? musicPlaylistShelfRenderer
        }
    }
}

/// Search wraps each ungrouped result row in its own `itemSectionRenderer`; its
/// `contents` are the usual card/row renderers.
nonisolated struct ItemSectionRenderer: Decodable {
    let contents: [CarouselItem]?
}

/// The "top result" hero card at the head of a search response. Its tap target
/// (artist/album/song) lives in `onTap`.
nonisolated struct MusicCardShelfRenderer: Decodable {
    let title: InnerTubeText?
    let subtitle: InnerTubeText?
    let thumbnail: ThumbnailRendererWrapper?
    let onTap: NavigationEndpoint?
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
            /// The "More" button beside the shelf title, navigating to a fuller
            /// listing (e.g. all of an artist's albums, or a home feed page).
            let moreContentButton: MoreButton?

            struct MoreButton: Decodable {
                let buttonRenderer: ButtonRenderer?
            }
        }
    }

    var title: String {
        header?.musicCarouselShelfBasicHeaderRenderer?.title?.text ?? ""
    }

    /// Tappable header buttons ("More", "Play all", …) carried beside the title.
    var headerButtons: [ButtonRenderer] {
        [header?.musicCarouselShelfBasicHeaderRenderer?.moreContentButton?.buttonRenderer]
            .compactMap { $0 }
    }
}

/// A tappable button renderer. We consume its label text and navigation target,
/// used for shelf-header actions like "More" (navigate) and "Play all" (play).
nonisolated struct ButtonRenderer: Decodable {
    let text: InnerTubeText?
    let navigationEndpoint: NavigationEndpoint?
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
    let menu: RendererMenu?

    /// The delete entity id for an uploaded album/release card, if present.
    var deleteEntityId: String? { menu?.deleteEntityId }

    /// The track's current like rating from its menu, if signed in and present
    /// (song/video cards carry it; albums/playlists don't).
    var likeStatus: LikeStatus? { menu?.likeStatus }
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
    let menu: RendererMenu?

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
        /// The playlist-scoped id needed to remove/reorder this row within an
        /// owned playlist (distinct from the plain videoId).
        let playlistSetVideoId: String?
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

    /// Artist/album links carried by the flex-column text runs (the title column
    /// is skipped; artist/album endpoints live in the byline columns).
    var entityLinks: [EntityLink] {
        (flexColumns ?? [])
            .dropFirst()
            .flatMap { $0.musicResponsiveListItemFlexColumnRenderer?.text?.entityLinks ?? [] }
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

    /// Playlist-scoped id for removing/reordering this row within an owned
    /// playlist (nil for rows that aren't playlist items).
    var playlistSetVideoId: String? { playlistItemData?.playlistSetVideoId }

    /// History-removal feedback token carried by the row's overflow menu.
    var feedbackToken: String? { menu?.feedbackToken }

    /// The track's current like rating from its menu, if signed in and present.
    var likeStatus: LikeStatus? { menu?.likeStatus }

    /// Delete entity id for an uploaded song row, if present.
    var deleteEntityId: String? { menu?.deleteEntityId }
}

// MARK: - Shared primitives

/// A renderer's overflow ("⋯") menu. We mine two service tokens from it: the
/// `feedbackToken` that removes a listening-history row, and the `entityId` that
/// deletes an uploaded item (which sits behind a confirm-delete dialog). Only the
/// keys we consume are modeled; the menu carries many more actions.
nonisolated struct RendererMenu: Decodable {
    let menuRenderer: MenuRenderer?

    struct MenuRenderer: Decodable {
        let items: [Item]?
        /// Prominent buttons above the overflow list — the track's like/dislike
        /// toggle lives here, carrying its *current* rating.
        let topLevelButtons: [TopLevelButton]?
    }

    struct TopLevelButton: Decodable {
        let likeButtonRenderer: LikeButton?

        struct LikeButton: Decodable {
            /// "LIKE" / "DISLIKE" / "INDIFFERENT" — the account-relative rating.
            let likeStatus: String?
        }
    }

    struct Item: Decodable {
        let menuServiceItemRenderer: ServiceItem?
        let menuNavigationItemRenderer: NavigationItem?
        /// A toggle action (e.g. "Add to liked songs" ⇄ "Remove"). The card-style
        /// (two-row) renderers carry the like state here rather than in a
        /// top-level like button.
        let toggleMenuServiceItemRenderer: ToggleItem?
    }

    struct ServiceItem: Decodable {
        let serviceEndpoint: ServiceEndpoint?
    }

    /// A menu toggle. The state it moves to when tapped is the *default*
    /// endpoint, so the current state is its inverse (tapping a not-liked song
    /// likes it). Home cards carry the like here; the "Listen again" feed carries
    /// a "Pin" toggle instead (no like), so this is simply absent there.
    struct ToggleItem: Decodable {
        let defaultServiceEndpoint: ToggleEndpoint?

        struct ToggleEndpoint: Decodable {
            let likeEndpoint: LikeEndpoint?
        }

        struct LikeEndpoint: Decodable {
            /// The rating this action sets ("LIKE"/"INDIFFERENT"/"DISLIKE").
            let status: String?
            let target: Target?

            struct Target: Decodable {
                /// A like toggle targets a videoId; a "save playlist" toggle
                /// targets a playlistId — only the former is a track rating.
                let videoId: String?
            }
        }
    }

    struct NavigationItem: Decodable {
        let navigationEndpoint: NavEndpoint?
    }

    struct NavEndpoint: Decodable {
        let confirmDialogEndpoint: ConfirmDialog?
    }

    struct ConfirmDialog: Decodable {
        let content: Content?

        struct Content: Decodable {
            let confirmDialogRenderer: Renderer?

            struct Renderer: Decodable {
                let confirmButton: ConfirmButton?

                struct ConfirmButton: Decodable {
                    let buttonRenderer: ButtonRenderer?

                    struct ButtonRenderer: Decodable {
                        let serviceEndpoint: ServiceEndpoint?
                    }
                }
            }
        }
    }

    struct ServiceEndpoint: Decodable {
        let feedbackEndpoint: FeedbackEndpoint?
        let deletePrivatelyOwnedEntityCommand: DeleteEntity?

        struct FeedbackEndpoint: Decodable { let feedbackToken: String? }
        struct DeleteEntity: Decodable { let entityId: String? }
    }

    /// The history-removal feedback token, if this menu carries one.
    var feedbackToken: String? {
        (menuRenderer?.items ?? [])
            .compactMap { $0.menuServiceItemRenderer?.serviceEndpoint?.feedbackEndpoint?.feedbackToken }
            .first
    }

    /// The track's current like rating from the menu, if present. Track-list rows
    /// carry it in a top-level like button; card-style (two-row) rows instead
    /// carry a like *toggle*, whose default action is the inverse of the current
    /// state (tapping a not-liked song likes it). nil when neither is present
    /// (signed out, or a non-track row) — the caller decides how to treat that.
    var likeStatus: LikeStatus? {
        if let raw = (menuRenderer?.topLevelButtons ?? [])
            .compactMap(\.likeButtonRenderer?.likeStatus).first {
            return LikeStatus(innerTube: raw)
        }
        for item in menuRenderer?.items ?? [] {
            guard let like = item.toggleMenuServiceItemRenderer?.defaultServiceEndpoint?.likeEndpoint,
                  like.target?.videoId != nil else { continue }
            switch like.status {
            case "LIKE":        return .indifferent   // tapping would like it → not liked
            case "INDIFFERENT": return .liked          // tapping would unlike it → liked
            default:            return nil
            }
        }
        return nil
    }

    /// The delete entity id for an uploaded item — either directly on a service
    /// item, or behind the confirm-delete dialog on a navigation item.
    var deleteEntityId: String? {
        for item in menuRenderer?.items ?? [] {
            if let id = item.menuServiceItemRenderer?.serviceEndpoint?
                .deletePrivatelyOwnedEntityCommand?.entityId {
                return id
            }
            if let id = item.menuNavigationItemRenderer?.navigationEndpoint?
                .confirmDialogEndpoint?.content?.confirmDialogRenderer?.confirmButton?
                .buttonRenderer?.serviceEndpoint?.deletePrivatelyOwnedEntityCommand?.entityId {
                return id
            }
        }
        return nil
    }
}

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

    /// Artist/album navigation links carried by individual runs (each run is a
    /// distinct name with its own browse endpoint).
    var entityLinks: [EntityLink] {
        (runs ?? []).compactMap { run in
            guard let browse = run.navigationEndpoint?.browseEndpoint,
                  let browseId = browse.browseId,
                  let kind = browse.kind,
                  !run.text.isEmpty else { return nil }
            return EntityLink(name: run.text, browseId: browseId, kind: kind)
        }
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
        let watchEndpointMusicSupportedConfigs: MusicConfigs?

        struct MusicConfigs: Decodable {
            let watchEndpointMusicConfig: MusicConfig?

            struct MusicConfig: Decodable {
                let musicVideoType: String?   // e.g. _ATV (song) / _OMV / _UGC / _PODCAST_EPISODE
            }
        }

        /// The track's "music video type", distinguishing a plain audio song
        /// (`…_ATV`) from a music video (`…_OMV`/`…_UGC`) or podcast episode.
        var musicVideoType: String? {
            watchEndpointMusicSupportedConfigs?.watchEndpointMusicConfig?.musicVideoType
        }
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

        /// The domain kind this browse endpoint targets, if it's one we navigate
        /// to (album / playlist / artist).
        var kind: HomeItem.Kind? {
            switch pageType {
            case "MUSIC_PAGE_TYPE_ALBUM":    return .album
            case "MUSIC_PAGE_TYPE_PLAYLIST": return .playlist
            case "MUSIC_PAGE_TYPE_ARTIST":   return .artist
            // A song/video byline often links to the uploader's channel rather
            // than a music artist page; both browse to an artist-style page, so
            // treat a channel as an artist (enables "Go to artist" on the row).
            case "MUSIC_PAGE_TYPE_USER_CHANNEL": return .artist
            default:                         break
            }
            // Uploaded (privately owned) artists/albums report
            // MUSIC_PAGE_TYPE_UNKNOWN, but their browse ids encode the kind.
            if let browseId {
                if browseId.contains("privately_owned_artist") { return .artist }
                if browseId.contains("privately_owned_release") { return .album }
            }
            return nil
        }
    }
}
