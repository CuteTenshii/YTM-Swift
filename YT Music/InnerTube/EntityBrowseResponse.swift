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

nonisolated final class EntityBrowseResponse: Decodable, @unchecked Sendable {
    let header: HeaderContainer?
    let contents: EntityContents?
    let continuationContents: ContinuationContents?
    let onResponseReceivedActions: [ResponseAction]?
    let onResponseReceivedCommands: [ResponseAction]?
    let microformat: Microformat?
    let frameworkUpdates: FrameworkUpdates?

    /// Entity-store mutations; a playlist's sort options resolve to commands here.
    struct FrameworkUpdates: Decodable {
        let entityBatchUpdate: BatchUpdate?

        struct BatchUpdate: Decodable {
            let mutations: [Mutation]?
        }

        struct Mutation: Decodable {
            let entityKey: String?
            let payload: Payload?
        }

        struct Payload: Decodable {
            let commandEntity: CommandEntity?
        }

        struct CommandEntity: Decodable {
            let command: ChipCloudRenderer.Endpoint?
        }

        /// The reload token of the command stored under `key`.
        func reloadToken(forKey key: String) -> String? {
            entityBatchUpdate?.mutations?
                .first { $0.entityKey == key }?
                .payload?.commandEntity?.command?.reloadToken
        }
    }

    struct Microformat: Decodable {
        let microformatDataRenderer: DataRenderer?

        struct DataRenderer: Decodable {
            let urlCanonical: String?
        }
    }

    struct ResponseAction: Decodable {
        let appendContinuationItemsAction: ContinuationItemsAction?
        let reloadContinuationItemsCommand: ContinuationItemsAction?
    }

    struct ContinuationItemsAction: Decodable {
        let continuationItems: [CarouselItem]?

        var continuationToken: String? {
            continuationItems?.reversed()
                .compactMap(\.continuationItemRenderer?.token).first
        }
    }

    var continuationItems: [CarouselItem] {
        (onResponseReceivedActions ?? [])
            .flatMap { $0.appendContinuationItemsAction?.continuationItems ?? [] }
            + (onResponseReceivedCommands ?? [])
            .flatMap { $0.reloadContinuationItemsCommand?.continuationItems ?? [] }
    }

    var continuationToken: String? {
        continuationContents?.shelf?.continuationToken
            ?? (onResponseReceivedActions ?? [])
                .compactMap { $0.appendContinuationItemsAction?.continuationToken }
                .first
            ?? (onResponseReceivedCommands ?? [])
                .compactMap { $0.reloadContinuationItemsCommand?.continuationToken }
                .first
    }

    struct ContinuationContents: Decodable {
        let musicShelfContinuation: MusicShelfRenderer?
        let musicPlaylistShelfContinuation: MusicShelfRenderer?
        /// A playlist filter chip's reloaded track section.
        let sectionListContinuation: BrowseResponse.SectionList?

        var shelf: MusicShelfRenderer? {
            musicShelfContinuation ?? musicPlaylistShelfContinuation
        }
    }

    // MARK: Header

    struct HeaderContainer: Decodable {
        // Albums/playlists (older layout) and artists use distinct renderers.
        let musicDetailHeaderRenderer: DetailHeader?
        let musicResponsiveHeaderRenderer: ResponsiveHeader?
        let musicImmersiveHeaderRenderer: ImmersiveHeader?
        /// Plain YouTube channels (a song/video byline target) use this lighter
        /// header: avatar + subscribe button + subscriber count, but no bio.
        let musicVisualHeaderRenderer: VisualHeader?

        struct VisualHeader: Decodable {
            let title: InnerTubeText?
            let foregroundThumbnail: ResponsiveHeader.ResponsiveThumbnail?
            let subscriptionButton: ImmersiveHeader.SubscriptionButton?
        }

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
            let subscriptionButton: SubscriptionButton?
            /// "Shuffle" — plays the artist's auto-generated mix in shuffled order.
            let playButton: RadioButton?
            /// "Start radio" — an endless radio/mix seeded from the artist.
            let startRadioButton: RadioButton?

            struct RadioButton: Decodable {
                let buttonRenderer: ButtonRenderer?

                struct ButtonRenderer: Decodable {
                    let navigationEndpoint: NavigationEndpoint?
                }
            }

            struct SubscriptionButton: Decodable {
                let subscribeButtonRenderer: SubscribeButtonRenderer?

                struct SubscribeButtonRenderer: Decodable {
                    let channelId: String?
                    let subscribed: Bool?
                    let serviceEndpoints: [ServiceEndpoint]?
                    /// Subscriber count, e.g. "79" or "1.2M" (channel headers).
                    let subscriberCountText: InnerTubeText?

                    struct ServiceEndpoint: Decodable {
                        let subscribeEndpoint: SubEndpoint?
                        let unsubscribeEndpoint: SubEndpoint?

                        struct SubEndpoint: Decodable {
                            let channelIds: [String]?
                            let params: String?
                        }
                    }
                }
            }
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
