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
        let bodyHeader = sections.compactMap(\.responsiveHeader).first
        var header = parseHeader(response.header, bodyResponsive: bodyHeader, fallback: fallback)
        let editableHeader = sections.lazy.compactMap(\.musicEditablePlaylistDetailHeaderRenderer).first
        header.collection?.privacy = editableHeader?.privacy
        header.collection?.collaborationPanel = editableHeader?.collaborationPanel
        header.collection?.voteOptions = editableHeader?.voteOptions ?? []

        var tracks: [Track] = []
        var shelves: [Shelf] = []
        var continuationToken = continuationToken(from: response.contents)
        var sortOptions: [PlaylistSortOption] = []
        var isManuallyOrdered = false
        var shufflePlaylistId: String?

        for section in sections {
            if let shelf = section.listShelf {
                if sortOptions.isEmpty {
                    sortOptions = self.sortOptions(shelf.header, updates: response.frameworkUpdates)
                }
                shufflePlaylistId = shufflePlaylistId ?? shelf.contents?
                    .lazy.compactMap { $0.musicResponsiveListItemRenderer?.navigationEndpoint?.watchPlaylistEndpoint?.playlistId }.first
                if sortOptions.isEmpty {
                    sortOptions = dropdownSortOptions(shelf)
                }
                isManuallyOrdered = isManuallyOrdered || self.isManuallyOrdered(shelf.header)
                tracks.append(contentsOf: parseTracks(shelf, startIndex: tracks.count + 1, header: header))
                continuationToken = shelf.continuationToken ?? continuationToken
            } else if let carousel = section.carousel {
                if let shelf = makeShelf(from: carousel) { shelves.append(shelf) }
            } else if let card = section.musicCardShelfRenderer {
                // A single highlighted item, like a profile's "Personal mix".
                if let item = HomeFeedParser.makeItem(
                    title: card.title?.text ?? "",
                    subtitle: card.subtitle?.text ?? "",
                    thumbnailURL: card.thumbnail?.bestURL,
                    endpoint: card.onTap
                ) {
                    shelves.append(Shelf(title: card.headerTitle.isEmpty ? "More" : card.headerTitle, items: [item]))
                }
            } else if let grid = section.gridRenderer {
                // Feed pages (e.g. a shelf's "More" → "Listen again") lay their
                // content out as grids rather than carousels.
                if let shelf = makeShelf(from: grid) { shelves.append(shelf) }
            }
        }

        let chipCloud = response.contents?.twoColumnBrowseResultsRenderer?.secondaryContents?
            .sectionListRenderer?.header?.chipCloudRenderer
        return EntityPage(
            header: header,
            tracks: tracks,
            shelves: shelves,
            continuationToken: continuationToken,
            shufflePlaylistId: shufflePlaylistId,
            isManuallyOrdered: isManuallyOrdered,
            shareURL: response.microformat?.microformatDataRenderer?.urlCanonical.flatMap(URL.init(string:)),
            filters: filters(chipCloud),
            sortOptions: sortOptions.isEmpty ? popupSortOptions(chipCloud) : sortOptions
        )
    }

    /// A filter or sort reload of a playlist's track section. The reloaded
    /// section carries its own filters and sort options (with the new
    /// selection, and tokens that keep it combined with the other control).
    static func parseTrackReload(_ response: EntityBrowseResponse, header: EntityHeader) -> EntityPage {
        let section = response.continuationContents?.sectionListContinuation
        let shelf = section?.contents?.lazy.compactMap(\.listShelf).first
            ?? response.continuationContents?.shelf
        let shelfSort = sortOptions(shelf?.header, updates: response.frameworkUpdates)
        return EntityPage(
            header: header,
            tracks: parseItems(shelf?.contents ?? [], startIndex: 1, header: header),
            shelves: [],
            continuationToken: shelf?.continuationToken,
            isManuallyOrdered: isManuallyOrdered(shelf?.header),
            filters: filters(section?.header?.chipCloudRenderer),
            sortOptions: shelfSort.isEmpty ? popupSortOptions(section?.header?.chipCloudRenderer) : shelfSort
        )
    }

    private static func dropdownSortOptions(_ shelf: MusicShelfRenderer) -> [PlaylistSortOption] {
        shelf.dropdownItems.compactMap { item in
            guard let title = item.label?.text, !title.isEmpty,
                  let browse = item.onSelectCommand?.browseEndpoint,
                  let browseId = browse.browseId, let params = browse.params else { return nil }
            return PlaylistSortOption(title: title, action: .browse(browseId: browseId, params: params),
                                      isSelected: item.isSelected ?? false)
        }
    }

    /// A podcast show's sort chip: its popup menu lists the orders, the current
    /// one marked with a check icon.
    private static func popupSortOptions(_ cloud: ChipCloudRenderer?) -> [PlaylistSortOption] {
        let items = (cloud?.chips ?? [])
            .compactMap { $0.chipCloudChipRenderer?.navigationEndpoint?.openPopupAction?.popup?
                .menuPopupRenderer?.items }
            .first ?? []
        return items.compactMap { item in
            guard let renderer = item.menuNavigationItemRenderer,
                  let title = renderer.text?.text, !title.isEmpty,
                  let token = renderer.navigationEndpoint?.reloadToken else { return nil }
            return PlaylistSortOption(title: title, action: .reload(token),
                                      isSelected: renderer.icon?.iconType == "CHECK")
        }
    }

    private static func filters(_ cloud: ChipCloudRenderer?) -> [PlaylistFilter] {
        (cloud?.chips ?? []).compactMap { chip in
            guard let renderer = chip.chipCloudChipRenderer,
                  let title = renderer.text?.text, !title.isEmpty,
                  let token = renderer.navigationEndpoint?.reloadToken else { return nil }
            return PlaylistFilter(title: title, token: token,
                                  clearToken: renderer.onDeselectedCommand?.reloadToken,
                                  isSelected: renderer.isSelected ?? false)
        }
    }

    private static func sortOptions(
        _ header: BrowseResponse.SectionList.Header?,
        updates: EntityBrowseResponse.FrameworkUpdates?
    ) -> [PlaylistSortOption] {
        let items = (header?.musicSideAlignedItemRenderer?.startItems ?? [])
            .flatMap { $0.sortFilterSubMenuRenderer?.subMenuItems ?? [] }
        return items.compactMap { item in
            guard let title = item.title, !title.isEmpty else { return nil }
            let action: PlaylistSortOption.Action
            if let edit = item.sortEdit {
                action = .edit(edit)
            } else if let key = item.navigationEndpoint?.executeEntityCommand?.commandEntityKey,
                      let token = updates?.reloadToken(forKey: key) {
                action = .reload(token)
            } else {
                return nil
            }
            return PlaylistSortOption(title: title, action: action, isSelected: item.selected ?? false)
        }
    }

    private static func isManuallyOrdered(_ header: BrowseResponse.SectionList.Header?) -> Bool {
        let items = (header?.musicSideAlignedItemRenderer?.startItems ?? [])
            .flatMap { $0.sortFilterSubMenuRenderer?.subMenuItems ?? [] }
        return items.contains { item in item.selected == true && item.playlistVideoOrder == 0 }
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

    /// An album's strapline artist(s), else a playlist's facepile owner.
    private static func byline(
        _ header: EntityBrowseResponse.HeaderContainer.ResponsiveHeader
    ) -> EntityByline? {
        if let runs = header.straplineTextOne?.runs, !runs.isEmpty {
            return EntityByline(
                runs: runs.map { EntityByline.Run(text: $0.text, link: $0.entityLink) },
                avatarURLs: [header.straplineThumbnail?.bestURL].compactMap { $0 }
            )
        }
        guard let stack = header.facepile?.avatarStackViewModel,
              let name = stack.text?.content, !name.isEmpty else { return nil }
        let link = stack.rendererContext?.commandContext?.onTap?.innertubeCommand?
            .browseEndpoint?.entityLink(named: name)
        return EntityByline(
            runs: [EntityByline.Run(text: name, link: link)],
            avatarURLs: (stack.avatars ?? []).prefix(3).compactMap { avatar in
                avatar.avatarViewModel?.image?.sources?.last.flatMap { URL(string: $0.url) }
            }
        )
    }

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
                artists: (detail.subtitle?.entityLinks ?? []).filter { $0.kind == .artist },
                content: collectionContent(fallback.kind, CollectionInfo())
            )
        }

        // The responsive header appears either at the top level or nested in the
        // body (the newer two-column album/playlist layout).
        if let responsive = container?.musicResponsiveHeaderRenderer ?? bodyResponsive {
            let subtitle = joinNonEmpty(responsive.subtitle?.text, responsive.secondSubtitle?.text)
            let artists = ((responsive.straplineTextOne?.entityLinks ?? [])
                + (responsive.subtitle?.entityLinks ?? [])).filter { $0.kind == .artist }
            return EntityHeader(
                title: responsive.title?.text ?? fallback.title,
                subtitle: subtitle.isEmpty ? fallback.subtitle : subtitle,
                description: responsive.description?.musicDescriptionShelfRenderer?
                    .description?.text ?? "",
                thumbnailURL: responsive.thumbnail?.musicThumbnailRenderer?.bestURL
                    ?? fallback.thumbnailURL,
                artists: artists,
                content: collectionContent(
                    fallback.kind,
                    CollectionInfo(isSaved: responsive.isSaved, byline: byline(responsive))
                )
            )
        }

        if let immersive = container?.musicImmersiveHeaderRenderer {
            // The immersive header's `thumbnail` is a wide background image — the
            // artist banner. `foregroundThumbnail`, when present, is the circular
            // artist portrait; otherwise the banner doubles as the avatar.
            let radioPlaylistId = immersive.playButton?.buttonRenderer?.navigationEndpoint?
                .playlistId
                ?? immersive.startRadioButton?.buttonRenderer?.navigationEndpoint?
                .playlistId
            return EntityHeader(
                title: immersive.title?.text ?? fallback.title,
                subtitle: immersive.subtitle?.text ?? fallback.subtitle,
                description: immersive.description?.text ?? "",
                thumbnailURL: immersive.foregroundThumbnail?.musicThumbnailRenderer?.bestURL
                    ?? immersive.thumbnail?.musicThumbnailRenderer?.bestURL
                    ?? fallback.thumbnailURL,
                content: .artist(ArtistPageInfo(
                    bannerURL: immersive.thumbnail?.musicThumbnailRenderer?.bestURL,
                    monthlyAudience: immersive.monthlyListenerCount?.text,
                    pronouns: immersive.pronouns?.text,
                    subscription: parseSubscription(immersive.subscriptionButton),
                    radioPlaylistId: radioPlaylistId,
                    startRadioPlaylistId: immersive.startRadioButton?.buttonRenderer?
                        .navigationEndpoint?.playlistId
                ))
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
                content: .profile(ArtistPageInfo(subscription: parseSubscription(visual.subscriptionButton)))
            )
        }

        // No recognizable header — fall back to what navigation gave us.
        return EntityHeader(
            title: fallback.title,
            subtitle: fallback.subtitle,
            description: "",
            thumbnailURL: fallback.thumbnailURL,
            content: collectionContent(fallback.kind, CollectionInfo())
        )
    }

    /// The content for a kind when the response had no matching header renderer; songs, videos and unknown are a bare feed page.
    private static func collectionContent(
        _ kind: ShelfItem.Kind,
        _ info: CollectionInfo
    ) -> EntityHeader.Content {
        switch kind {
        case .album: .album(info)
        case .playlist: .playlist(info)
        case .podcast: .podcast(PodcastInfo(isSaved: info.isSaved, byline: info.byline))
        case .artist: .artist(ArtistPageInfo())
        case .profile: .profile(ArtistPageInfo())
        default: .feed
        }
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

    static func parseItems(
        _ items: [CarouselItem],
        startIndex: Int,
        header: EntityHeader
    ) -> [Track] {
        var index = startIndex
        return items.compactMap { item in
            if let episode = item.musicMultiRowListItemRenderer {
                defer { index += 1 }
                return Track(
                    index: index,
                    title: episode.title?.text ?? "",
                    subtitle: episode.subtitle?.text ?? "",
                    duration: episode.durationText,
                    thumbnailURL: episode.thumbnail?.bestURL ?? header.thumbnailURL,
                    videoId: episode.videoId,
                    artists: header.byline?.runs.compactMap(\.link) ?? [],
                    likeStatus: episode.menu?.likeStatus ?? .indifferent
                )
            }
            guard let row = item.musicResponsiveListItemRenderer,
                  row.navigationEndpoint?.watchPlaylistEndpoint == nil else { return nil }
            let columns = row.textColumns
            guard let title = columns.first else { return nil }

            defer { index += 1 }
            let links = row.entityLinks
            let albumLink = links.first { $0.kind == .album }
            let rowArtists = links.filter { $0.kind == .artist }

            // Default: artists + subtitle come from the row itself. On an album
            // page, a column linking to an album is the page's own album.
            var artists = rowArtists
            var subtitle = row.textColumnRuns.dropFirst()
                .filter { header.kind != .album || !$0.entityLinks.contains { $0.kind == .album } }
                .map(\.text)
                .joined(separator: " • ")

            // Album tracks usually omit a per-row artist — it's the album artist,
            // carried only in the header. Adopt the header artist for the links so
            // the context menu / Now Playing resolve correctly. Only overwrite the
            // visible byline when the row would otherwise be blank; real albums put
            // a useful "plays" column here, so keep it.
            if rowArtists.isEmpty, header.kind == .album, !header.artists.isEmpty {
                artists = header.artists
                if subtitle.isEmpty {
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
                likeStatus: row.likeStatus ?? .indifferent,
                vote: row.engagementBar?.vote
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
            unsubscribeParams: unsubscribeParams,
            isEnabled: renderer.enabled ?? true
        )
    }

    // MARK: - Carousels (reuse the Home shelf shape)

    private static func makeShelf(from carousel: MusicCarouselShelfRenderer) -> Shelf? {
        let items = (carousel.contents ?? []).compactMap { HomeFeedParser.makeItem(from: $0) }
        guard !items.isEmpty else { return nil }
        let title = carousel.title.isEmpty ? "More" : carousel.title
        return Shelf(
            title: title, items: items, buttons: HomeFeedParser.shelfButtons(from: carousel),
            rowsPerColumn: carousel.rowsPerColumn,
            strapline: carousel.strapline, avatarURL: carousel.avatarURL
        )
    }

    private static func makeShelf(from grid: GridRenderer) -> Shelf? {
        let items = (grid.items ?? []).compactMap { HomeFeedParser.makeItem(from: $0) }
        guard !items.isEmpty else { return nil }
        return Shelf(title: grid.title.isEmpty ? "More" : grid.title, items: items)
    }

    // MARK: - Helpers

    private static func joinNonEmpty(_ parts: String?...) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • ")
    }
}
