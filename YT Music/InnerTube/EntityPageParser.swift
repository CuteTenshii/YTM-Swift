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
        let sections = collectSections(response.contents)
        // Non-uploaded albums/playlists carry no top-level `header`; their
        // responsive header sits inside the body's section list instead.
        let bodyHeader = sections.compactMap(\.musicResponsiveHeaderRenderer).first
        let header = parseHeader(response.header, bodyResponsive: bodyHeader, fallback: fallback)

        var tracks: [Track] = []
        var shelves: [HomeShelf] = []
        var continuationToken = continuationToken(from: response.contents)

        for section in sections {
            if let shelf = section.listShelf {
                tracks.append(contentsOf: parseTracks(shelf, startIndex: tracks.count + 1, header: header))
                continuationToken = shelf.continuationToken ?? continuationToken
            } else if let carousel = section.carousel {
                if let shelf = makeShelf(from: carousel) { shelves.append(shelf) }
            } else if let grid = section.gridRenderer {
                // Feed pages (e.g. a shelf's "More" → "Listen again") lay their
                // content out as grids rather than carousels.
                if let shelf = makeShelf(from: grid) { shelves.append(shelf) }
            }
        }

        return EntityPage(
            header: header,
            tracks: tracks,
            shelves: shelves,
            continuationToken: continuationToken
        )
    }

    static func parseContinuation(
        _ response: EntityBrowseResponse,
        startIndex: Int,
        header: EntityHeader
    ) -> (tracks: [Track], continuationToken: String?) {
        let items = response.continuationContents?.shelf?.contents
            ?? response.continuationItems
        return (
            parseItems(items ?? [], startIndex: startIndex, header: header),
            response.continuationToken
        )
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

    private static func continuationToken(
        from contents: EntityBrowseResponse.EntityContents?
    ) -> String? {
        guard let contents else { return nil }
        let single = contents.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?
            .content?.sectionListRenderer?.continuationToken
        let twoColumn = contents.twoColumnBrowseResultsRenderer
        return single
            ?? twoColumn?.tabs?.first?.tabRenderer?.content?.sectionListRenderer?.continuationToken
            ?? twoColumn?.secondaryContents?.sectionListRenderer?.continuationToken
    }

    private static func sectionList(
        fromTabs tabs: [BrowseResponse.Tab]?
    ) -> [BrowseResponse.SectionContent] {
        tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents ?? []
    }

    // MARK: - Header

    private static func parseHeader(
        _ container: EntityBrowseResponse.HeaderContainer?,
        bodyResponsive: EntityBrowseResponse.HeaderContainer.ResponsiveHeader?,
        fallback: EntityDestination
    ) -> EntityHeader {
        if let detail = container?.musicDetailHeaderRenderer {
            let subtitle = joinNonEmpty(detail.subtitle?.text, detail.secondSubtitle?.text)
            return EntityHeader(
                title: detail.title?.text ?? fallback.title,
                subtitle: subtitle,
                description: detail.description?.text ?? "",
                thumbnailURL: detail.thumbnail?.croppedSquareThumbnailRenderer?.bestURL
                    ?? fallback.thumbnailURL,
                kind: fallback.kind,
                artists: (detail.subtitle?.entityLinks ?? []).filter { $0.kind == .artist },
                privacy: PlaylistPrivacy(subtitleText: subtitle)
            )
        }

        // The responsive header appears either at the top level or nested in the
        // body (the newer two-column album/playlist layout).
        if let responsive = container?.musicResponsiveHeaderRenderer ?? bodyResponsive {
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
                artists: artists,
                privacy: PlaylistPrivacy(subtitleText: subtitle)
            )
        }

        if let immersive = container?.musicImmersiveHeaderRenderer {
            // The immersive header's `thumbnail` is a wide background image — the
            // artist banner. `foregroundThumbnail`, when present, is the circular
            // artist portrait; otherwise the banner doubles as the avatar.
            let radioPlaylistId = immersive.playButton?.buttonRenderer?.navigationEndpoint?
                .watchPlaylistEndpoint?.playlistId
                ?? immersive.startRadioButton?.buttonRenderer?.navigationEndpoint?
                .watchPlaylistEndpoint?.playlistId
            return EntityHeader(
                title: immersive.title?.text ?? fallback.title,
                subtitle: immersive.subtitle?.text ?? fallback.subtitle,
                description: immersive.description?.text ?? "",
                thumbnailURL: immersive.foregroundThumbnail?.musicThumbnailRenderer?.bestURL
                    ?? immersive.thumbnail?.musicThumbnailRenderer?.bestURL
                    ?? fallback.thumbnailURL,
                bannerURL: immersive.thumbnail?.musicThumbnailRenderer?.bestURL,
                kind: fallback.kind,
                subscription: parseSubscription(immersive.subscriptionButton),
                radioPlaylistId: radioPlaylistId
            )
        }

        // Plain YouTube channels (a video/song byline target) use a lighter
        // header: avatar (`foregroundThumbnail`) + subscribe button + subscriber
        // count, but no bio. Reuse the artist subscribe parsing.
        if let visual = container?.musicVisualHeaderRenderer {
            let subscribers = visual.subscriptionButton?.subscribeButtonRenderer?
                .subscriberCountText?.text ?? ""
            return EntityHeader(
                title: visual.title?.text ?? fallback.title,
                subtitle: formatSubscribers(subscribers),
                description: "",
                thumbnailURL: visual.foregroundThumbnail?.musicThumbnailRenderer?.bestURL
                    ?? fallback.thumbnailURL,
                kind: fallback.kind,
                subscription: parseSubscription(visual.subscriptionButton)
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

    /// Formats a subscriber count for display. YouTube sometimes returns just the
    /// number ("79") and sometimes the full "1.2M subscribers"; append the noun
    /// only when it's missing.
    private static func formatSubscribers(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        return text.lowercased().contains("subscrib") ? text : "\(text) subscribers"
    }

    // MARK: - Tracks

    private static func parseTracks(
        _ shelf: MusicShelfRenderer,
        startIndex: Int,
        header: EntityHeader
    ) -> [Track] {
        parseItems(shelf.contents ?? [], startIndex: startIndex, header: header)
    }

    private static func parseItems(
        _ items: [CarouselItem],
        startIndex: Int,
        header: EntityHeader
    ) -> [Track] {
        var index = startIndex
        return items.compactMap { item in
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
            // carried only in the header. Adopt the header artist for the links so
            // the context menu / Now Playing resolve correctly. Only overwrite the
            // visible byline when the row would otherwise be blank or leak the
            // album name (uploaded albums); real albums put a useful "plays" column
            // here, so keep it.
            if rowArtists.isEmpty, header.kind == .album, !header.artists.isEmpty {
                artists = header.artists
                if subtitle.isEmpty || subtitle == albumLink?.name {
                    subtitle = header.artists.map(\.name).joined(separator: ", ")
                }
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
                albumLink: albumLink,
                playlistSetVideoId: row.playlistSetVideoId,
                canRemoveFromPlaylist: row.offersPlaylistRemoval,
                likeStatus: row.likeStatus ?? .indifferent
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
        return HomeShelf(title: title, items: items, buttons: HomeFeedParser.shelfButtons(from: carousel))
    }

    private static func makeShelf(from grid: GridRenderer) -> HomeShelf? {
        let items = (grid.items ?? []).compactMap { HomeFeedParser.makeItem(from: $0) }
        guard !items.isEmpty else { return nil }
        return HomeShelf(title: grid.title.isEmpty ? "More" : grid.title, items: items)
    }

    // MARK: - Helpers

    private static func joinNonEmpty(_ parts: String?...) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • ")
    }
}
