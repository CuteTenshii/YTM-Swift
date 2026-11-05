//
//  HomeFeedParser.swift
//  YT Music
//
//

import Foundation

nonisolated enum HomeFeedParser {

    static func parse(_ response: BrowseResponse) -> HomeFeed {
        let tab = response.contents?
            .singleColumnBrowseResultsRenderer?
            .tabs?.first?
            .tabRenderer
        let content = tab?.content
        let sectionList = content?.sectionListRenderer
        let sections = sectionList?.contents ?? []

        let shelves = sections.compactMap { shelf(from: $0) }
        let sectionChips = sections.flatMap { section in
            (section.chipCloudRenderer?.chips ?? []).compactMap { chip -> FeedChip? in
                guard let renderer = chip.chipCloudChipRenderer,
                      let title = renderer.text?.text,
                      let browse = renderer.navigationEndpoint?.browseEndpoint,
                      let browseId = browse.browseId,
                      !title.isEmpty else { return nil }
                return FeedChip(
                    id: "\(browseId)|\(browse.params ?? title)",
                    title: title,
                    browseId: browseId,
                    params: browse.params
                )
            }
        }
        let topChips = (content?.sectionListRenderer?.header?.chipCloudRenderer?.chips ?? []).compactMap { chip -> FeedChip? in
            guard let renderer = chip.chipCloudChipRenderer,
                  let title = renderer.text?.text,
                  let browse = renderer.navigationEndpoint?.browseEndpoint,
                  let browseId = browse.browseId,
                  !title.isEmpty else { return nil }
            return FeedChip(
                id: "\(browseId)|\(browse.params ?? title)",
                title: title,
                browseId: browseId,
                params: browse.params
            )
        }
        var chips = topChips + sectionChips
        var seen = Set<String>()
        chips.removeAll { !seen.insert($0.id).inserted }
        return HomeFeed(
            shelves: shelves,
            chips: chips,
            continuation: sectionList?.continuationToken,
            visitorData: response.responseContext?.visitorData
        )
    }

    static func parseContinuation(_ response: BrowseResponse) -> HomeFeed {
        let sectionList = response.continuationContents?.sectionListContinuation
        return HomeFeed(
            shelves: (sectionList?.contents ?? []).compactMap { shelf(from: $0) },
            continuation: sectionList?.continuationToken,
            visitorData: response.responseContext?.visitorData
        )
    }

    // MARK: - Shelves

    private static func shelf(from section: BrowseResponse.SectionContent) -> Shelf? {
        guard let carousel = section.carousel else { return nil }

        let items = (carousel.contents ?? []).compactMap { makeItem(from: $0) }
        guard !items.isEmpty else { return nil }

        let title = carousel.title.isEmpty ? String(localized: "shelf.more") : carousel.title
        return Shelf(
            title: title, items: items, buttons: shelfButtons(from: carousel),
            rowsPerColumn: carousel.rowsPerColumn,
            strapline: carousel.strapline, avatarURL: carousel.avatarURL
        )
    }

    // MARK: - Shelf header buttons

    static func shelfButtons(from carousel: MusicCarouselShelfRenderer) -> [ShelfButton] {
        carousel.headerButtons.compactMap { makeShelfButton(from: $0, pageTitle: carousel.title) }
    }

    static func makeShelfButton(from button: ButtonRenderer, pageTitle: String) -> ShelfButton? {
        let label = button.text?.text ?? ""
        guard !label.isEmpty else { return nil }

        if let watch = button.navigationEndpoint?.watchEndpoint, let playlistId = watch.playlistId {
            return ShelfButton(title: label, action: .play(videoId: watch.videoId, playlistId: playlistId))
        }
        if let browse = button.navigationEndpoint?.browseEndpoint, let browseId = browse.browseId {
            let destination = EntityDestination(
                browseId: browseId,
                kind: browse.kind ?? .unknown,
                title: pageTitle.isEmpty ? label : pageTitle,
                subtitle: "",
                thumbnailURL: nil
            )
            return ShelfButton(title: label, action: .navigate(destination))
        }
        return nil
    }

    static func makeItem(from carouselItem: CarouselItem) -> ShelfItem? {
        if let row = carouselItem.musicTwoRowItemRenderer {
            return makeItem(from: row)
        }
        if let row = carouselItem.musicResponsiveListItemRenderer {
            return makeItem(from: row)
        }
        return nil
    }

    // MARK: - Two-row cards

    static func makeItem(from row: MusicTwoRowItemRenderer) -> ShelfItem? {
        let title = row.title?.text ?? ""
        guard !title.isEmpty else { return nil }

        let (kind, videoId, browseId, resolvedPlaylistId) = resolve(row.navigationEndpoint)
        let playlistId = resolvedPlaylistId
            ?? collectionPlaylistId(kind: kind, browseId: browseId, play: row.overlayPlayEndpoint)
        let links = row.subtitle?.entityLinks ?? []

        return ShelfItem(
            title: title,
            subtitle: row.subtitle?.text ?? "",
            thumbnailURL: row.thumbnailRenderer?.bestURL,
            kind: kind,
            videoId: videoId,
            browseId: browseId,
            playlistId: playlistId,
            artists: links.filter { $0.kind == .artist },
            albumLink: links.first { $0.kind == .album },
            deleteEntityId: row.deleteEntityId,
            likeStatus: row.likeStatus,
            editablePlaylistId: row.menu?.editablePlaylistId
        )
    }

    // MARK: - List rows

    static func makeItem(from row: MusicResponsiveListItemRenderer) -> ShelfItem? {
        let columns = row.textColumns
        guard let title = columns.first else { return nil }

        let subtitle = columns.dropFirst().joined(separator: " • ")
        var (kind, videoId, browseId, playlistId) = resolve(row.playEndpoint)
        // Uploaded and history rows carry the video id in `playlistItemData`, not a play endpoint.
        if videoId == nil, let id = row.trackVideoId {
            videoId = id
            if kind == .unknown { kind = .song }
        }
        playlistId = playlistId
            ?? collectionPlaylistId(kind: kind, browseId: browseId, play: row.overlayPlayEndpoint)
        let links = row.entityLinks

        return ShelfItem(
            title: title,
            subtitle: subtitle,
            thumbnailURL: row.thumbnail?.bestURL,
            kind: kind,
            videoId: videoId,
            browseId: browseId,
            playlistId: playlistId,
            artists: links.filter { $0.kind == .artist },
            albumLink: links.first { $0.kind == .album },
            deleteEntityId: row.deleteEntityId,
            likeStatus: row.likeStatus,
            chartRank: row.chartRank,
            editablePlaylistId: row.menu?.editablePlaylistId
        )
    }

    // MARK: - Endpoint resolution

    static func makeItem(
        title: String,
        subtitle: String,
        thumbnailURL: URL?,
        endpoint: NavigationEndpoint?
    ) -> ShelfItem? {
        guard !title.isEmpty else { return nil }
        let (kind, videoId, browseId, playlistId) = resolve(endpoint)
        return ShelfItem(
            title: title,
            subtitle: subtitle,
            thumbnailURL: thumbnailURL,
            kind: kind,
            videoId: videoId,
            browseId: browseId,
            playlistId: playlistId
        )
    }

    private static func collectionPlaylistId(
        kind: ShelfItem.Kind, browseId: String?, play: NavigationEndpoint?
    ) -> String? {
        guard kind == .album || kind == .playlist else { return nil }
        if let id = play?.watchPlaylistEndpoint?.playlistId ?? play?.watchEndpoint?.playlistId {
            return id
        }
        guard kind == .playlist, let browseId, browseId.hasPrefix("VL") else { return nil }
        return String(browseId.dropFirst(2))
    }

    private static func resolve(
        _ endpoint: NavigationEndpoint?
    ) -> (ShelfItem.Kind, String?, String?, String?) {
        if let watch = endpoint?.watchEndpoint, let videoId = watch.videoId {
            // A watch endpoint with a playlist is typically a music video or mix.
            let kind: ShelfItem.Kind = watch.playlistId == nil ? .song : .video
            return (kind, videoId, nil, watch.playlistId)
        }

        if let browse = endpoint?.browseEndpoint, let browseId = browse.browseId {
            switch browse.pageType {
            case "MUSIC_PAGE_TYPE_ALBUM":    return (.album, nil, browseId, nil)
            case "MUSIC_PAGE_TYPE_PLAYLIST": return (.playlist, nil, browseId, nil)
            case "MUSIC_PAGE_TYPE_ARTIST":   return (.artist, nil, browseId, nil)
            case "MUSIC_PAGE_TYPE_USER_CHANNEL": return (.profile, nil, browseId, nil)
            case "MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE": return (.podcast, nil, browseId, nil)
            case "MUSIC_PAGE_TYPE_LIBRARY_ARTIST":
                return (.artist, nil, browseId.hasPrefix("MPLA") ? String(browseId.dropFirst(4)) : browseId, nil)
            default:                         return (.unknown, nil, browseId, nil)
            }
        }

        return (.unknown, nil, nil, nil)
    }
}
