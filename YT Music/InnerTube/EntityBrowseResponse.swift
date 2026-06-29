//
//  EntityBrowseResponse.swift
//  YT Music
//
//  Decodable models for `browse` responses that describe a single entity —
//  an album, playlist, or artist. These share the section/shelf renderers from
//  BrowseResponse.swift but add the various header renderers YouTube uses and
//  the newer two-column layout.
//

import Foundation

struct EntityBrowseResponse: Decodable {
    let header: HeaderContainer?
    let contents: EntityContents?

    // MARK: Header

    struct HeaderContainer: Decodable {
        // Albums/playlists (older layout) and artists use distinct renderers.
        let musicDetailHeaderRenderer: DetailHeader?
        let musicResponsiveHeaderRenderer: ResponsiveHeader?
        let musicImmersiveHeaderRenderer: ImmersiveHeader?

        struct DetailHeader: Decodable {
            let title: InnerTubeText?
            let subtitle: InnerTubeText?
            let secondSubtitle: InnerTubeText?
            let description: InnerTubeText?
            let thumbnail: CroppedThumbnail?
        }

        struct ResponsiveHeader: Decodable {
            let title: InnerTubeText?
            let subtitle: InnerTubeText?
            let straplineTextOne: InnerTubeText?
            let secondSubtitle: InnerTubeText?
            let thumbnail: ResponsiveThumbnail?
            let description: DescriptionWrapper?

            struct ResponsiveThumbnail: Decodable {
                let musicThumbnailRenderer: ThumbnailRendererWrapper.MusicThumbnailRenderer?
            }

            struct DescriptionWrapper: Decodable {
                let musicDescriptionShelfRenderer: Shelf?
                struct Shelf: Decodable { let description: InnerTubeText? }
            }
        }

        struct ImmersiveHeader: Decodable {
            let title: InnerTubeText?
            let subtitle: InnerTubeText?
            let description: InnerTubeText?
            let thumbnail: ResponsiveHeader.ResponsiveThumbnail?
            let foregroundThumbnail: ResponsiveHeader.ResponsiveThumbnail?
        }

        /// Detail-header artwork is nested under `croppedSquareThumbnailRenderer`.
        struct CroppedThumbnail: Decodable {
            let croppedSquareThumbnailRenderer: ThumbnailRendererWrapper.MusicThumbnailRenderer?
        }
    }

    // MARK: Body

    struct EntityContents: Decodable {
        let singleColumnBrowseResultsRenderer: BrowseResponse.SingleColumn?
        let twoColumnBrowseResultsRenderer: TwoColumn?

        struct TwoColumn: Decodable {
            let tabs: [BrowseResponse.Tab]?
            let secondaryContents: Secondary?

            struct Secondary: Decodable {
                let sectionListRenderer: BrowseResponse.SectionList?
            }
        }
    }
}
