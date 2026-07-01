//
//  EntityPageParser.swift
//  YT Music
//
//  Maps a raw `EntityBrowseResponse` into the clean `EntityPage` model. Handles
//  album/playlist/artist headers (three renderer variants) and bodies in both
//  the single-column and newer two-column layouts.
//

import Foundation

nonisolated enum EntityPageParser {

    static func parse(_ response: EntityBrowseResponse, fallback: EntityDestination) -> EntityPage {
        let header = parseHeader(response.header, fallback: fallback)
        let sections = collectSections(response.contents)

        var tracks: [Track] = []
        var shelves: [HomeShelf] = []

        for section in sections {
            if let shelf = section.listShelf {
                tracks.append(contentsOf: parseTracks(shelf, startIndex: tracks.count + 1, header: header))
            } else if let carousel = section.carousel {
                if let shelf = makeShelf(from: carousel) { shelves.append(shelf) }
            }
        }

        return EntityPage(header: header, tracks: tracks, shelves: shelves)
    }

    // MARK: - Sections

    /// Gathers section content from whichever layout the response used.
    private static func collectSections(
        _ contents: EntityBrowseResponse.EntityContents?
    ) -> [BrowseResponse.SectionContent] {
        guard let contents else { return [] }
        var sections: [BrowseResponse.SectionContent] = []

        sections += sectionList(fromTabs: contents.singleColumnBrowseResultsRenderer?.tabs)

        if let two = contents.twoColumnBrowseResultsRenderer {
            sections += sectionList(fromTabs: two.tabs)
            sections += two.secondaryContents?.sectionListRenderer?.contents ?? []
        }

        return sections
    }

    private static func sectionList(
        fromTabs tabs: [BrowseResponse.Tab]?
    ) -> [BrowseResponse.SectionContent] {
        tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents ?? []
    }

    // MARK: - Header

    private static func parseHeader(
        _ container: EntityBrowseResponse.HeaderContainer?,
        fallback: EntityDestination
    ) -> EntityHeader {
        if let detail = container?.musicDetailHeaderRenderer {
            return EntityHeader(
                title: detail.title?.text ?? fallback.title,
                subtitle: joinNonEmpty(detail.subtitle?.text, detail.secondSubtitle?.text),
                description: detail.description?.text ?? "",
                thumbnailURL: detail.thumbnail?.croppedSquareThumbnailRenderer?.bestURL
                    ?? fallback.thumbnailURL,
                kind: fallback.kind,
                artists: (detail.subtitle?.entityLinks ?? []).filter { $0.kind == .artist }
            )
        }

        if let responsive = container?.musicResponsiveHeaderRenderer {
            let subtitle = joinNonEmpty(
                responsive.straplineTextOne?.text,
                responsive.subtitle?.text,
                responsive.secondSubtitle?.text
            )
            let artists = ((responsive.straplineTextOne?.entityLinks ?? [])
                + (responsive.subtitle?.entityLinks ?? [])).filter { $0.kind == .artist }
            return EntityHeader(
                title: responsive.title?.text ?? fallback.title,
                subtitle: subtitle.isEmpty ? fallback.subtitle : subtitle,
                description: responsive.description?.musicDescriptionShelfRenderer?
                    .description?.text ?? "",
                thumbnailURL: responsive.thumbnail?.musicThumbnailRenderer?.bestURL
                    ?? fallback.thumbnailURL,
                kind: fallback.kind,
                artists: artists
            )
        }

        if let immersive = container?.musicImmersiveHeaderRenderer {
            return EntityHeader(
                title: immersive.title?.text ?? fallback.title,
                subtitle: immersive.subtitle?.text ?? fallback.subtitle,
                description: immersive.description?.text ?? "",
                thumbnailURL: immersive.foregroundThumbnail?.musicThumbnailRenderer?.bestURL
                    ?? immersive.thumbnail?.musicThumbnailRenderer?.bestURL
                    ?? fallback.thumbnailURL,
                kind: fallback.kind,
                subscription: parseSubscription(immersive.subscriptionButton)
            )
        }

        // No recognizable header — fall back to what navigation gave us.
        return EntityHeader(
            title: fallback.title,
            subtitle: fallback.subtitle,
            description: "",
            thumbnailURL: fallback.thumbnailURL,
            kind: fallback.kind
        )
    }

    // MARK: - Tracks

    private static func parseTracks(
        _ shelf: MusicShelfRenderer,
        startIndex: Int,
        header: EntityHeader
    ) -> [Track] {
        var index = startIndex
        return (shelf.contents ?? []).compactMap { item in
            guard let row = item.musicResponsiveListItemRenderer else { return nil }
            let columns = row.textColumns
            guard let title = columns.first else { return nil }

            defer { index += 1 }
            let links = row.entityLinks
            let albumLink = links.first { $0.kind == .album }
            let rowArtists = links.filter { $0.kind == .artist }

            // Default: artists + subtitle come from the row itself.
            var artists = rowArtists
            var subtitle = columns.dropFirst().joined(separator: " • ")

            // Album tracks usually omit a per-row artist — it's the album artist,
            // carried only in the header (uploaded albums even leave the row's
            // artist column empty, so the album name would otherwise leak into the
            // subtitle). Inherit the header artist for both the links and text.
            if rowArtists.isEmpty, header.kind == .album, !header.artists.isEmpty {
                artists = header.artists
                subtitle = header.artists.map(\.name).joined(separator: ", ")
            }

            return Track(
                index: index,
                title: title,
                subtitle: subtitle,
                duration: row.durationText,
                // Album/uploaded track rows carry no per-row artwork — fall back
                // to the album cover instead of a blank placeholder.
                thumbnailURL: row.thumbnail?.bestURL ?? header.thumbnailURL,
                videoId: row.trackVideoId,
                artists: artists,
                albumLink: albumLink
            )
        }
    }

    // MARK: - Subscription

    /// Turns the artist header's subscribe button into our `ArtistSubscription`,
    /// pulling the channel id, current subscribed state, and the params for the
    /// subscribe / unsubscribe service endpoints.
    private static func parseSubscription(
        _ button: EntityBrowseResponse.HeaderContainer.ImmersiveHeader.SubscriptionButton?
    ) -> ArtistSubscription? {
        guard let renderer = button?.subscribeButtonRenderer else { return nil }

        var channelId = renderer.channelId
        var subscribeParams: String?
        var unsubscribeParams: String?
        for endpoint in renderer.serviceEndpoints ?? [] {
            if let subscribe = endpoint.subscribeEndpoint {
                subscribeParams = subscribe.params
                channelId = channelId ?? subscribe.channelIds?.first
            }
            if let unsubscribe = endpoint.unsubscribeEndpoint {
                unsubscribeParams = unsubscribe.params
                channelId = channelId ?? unsubscribe.channelIds?.first
            }
        }

        guard let channelId else { return nil }
        return ArtistSubscription(
            channelId: channelId,
            isSubscribed: renderer.subscribed ?? false,
            subscribeParams: subscribeParams,
            unsubscribeParams: unsubscribeParams
        )
    }

    // MARK: - Carousels (reuse the Home shelf shape)

    private static func makeShelf(from carousel: MusicCarouselShelfRenderer) -> HomeShelf? {
        let items = (carousel.contents ?? []).compactMap { HomeFeedParser.makeItem(from: $0) }
        guard !items.isEmpty else { return nil }
        let title = carousel.title.isEmpty ? "More" : carousel.title
        return HomeShelf(title: title, items: items)
    }

    // MARK: - Helpers

    private static func joinNonEmpty(_ parts: String?...) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • ")
    }
}
