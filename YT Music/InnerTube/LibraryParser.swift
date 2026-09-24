//
//  LibraryParser.swift
//  YT Music
//
//  Parses the library browse pages (`FEmusic_library_landing` and each filter
//  chip's page, e.g. `FEmusic_liked_playlists`) into shelves. They mix grids
//  (playlists/albums) and flat list shelves (songs/artists), all built from the
//  same card renderers as Home, so we reuse `HomeShelf` / `HomeItem` and
//  `HomeFeedParser.makeItem`. Each listing is paginated via continuations.
//

import Foundation

nonisolated enum LibraryParser {

    static func parse(_ response: BrowseResponse) -> LibraryPage {
        let sectionList = response.contents?
            .singleColumnBrowseResultsRenderer?
            .tabs?.first?
            .tabRenderer?.content?
            .sectionListRenderer
        let sections = sectionList?.contents ?? []

        let chips = (sectionList?.header?.musicSideAlignedItemRenderer?.startItems ?? [])
            .flatMap { $0.chipCloudRenderer?.chips ?? [] }
            .compactMap(chip(from:))
        let continuation = sections.lazy
            .compactMap { $0.gridRenderer?.continuationToken ?? $0.listShelf?.continuationToken }
            .first

        var shelves: [HomeShelf] = []
        var tracks: [Track] = []
        for section in sections {
            if let list = section.listShelf, isSongList(list.contents) {
                tracks += songs(list.contents)
            } else if let shelf = shelf(from: section) {
                shelves.append(shelf)
            }
        }
        return LibraryPage(shelves: shelves, tracks: tracks, chips: chips, continuation: continuation)
    }

    /// The next page of a listing: song rows as tracks, anything else as a
    /// single untitled shelf.
    static func parseContinuation(_ response: BrowseResponse) -> LibraryPage {
        let grid = response.continuationContents?.gridContinuation
        let list = response.continuationContents?.musicShelfContinuation
        let continuation = grid?.continuationToken ?? list?.continuationToken
        if let rows = list?.contents, isSongList(rows) {
            return LibraryPage(shelves: [], tracks: songs(rows), continuation: continuation)
        }
        let items = playableItems(grid?.items ?? list?.contents)
        return LibraryPage(
            shelves: items.isEmpty ? [] : [HomeShelf(title: "", items: items)],
            continuation: continuation
        )
    }

    private static func isSongList(_ contents: [CarouselItem]?) -> Bool {
        let items = playableItems(contents)
        return !items.isEmpty && items.allSatisfy { $0.kind == .song || $0.kind == .video }
    }

    /// Song rows parsed like a playlist's tracks, numbered from 1.
    private static func songs(_ contents: [CarouselItem]?) -> [Track] {
        let header = EntityHeader(title: "", subtitle: "", description: "", thumbnailURL: nil, kind: .unknown)
        return EntityPageParser.parseItems(contents ?? [], startIndex: 1, header: header)
            .filter { $0.videoId != nil }
            .enumerated()
            .map { offset, track in
                var track = track
                track.index = offset + 1
                return track
            }
    }

    private static func chip(from chip: ChipCloudRenderer.Chip) -> HomeChip? {
        guard let renderer = chip.chipCloudChipRenderer,
              let title = renderer.text?.text, !title.isEmpty,
              let browse = renderer.navigationEndpoint?.browse,
              let browseId = browse.browseId else { return nil }
        return HomeChip(id: "\(browseId)|\(browse.params ?? title)", title: title,
                        browseId: browseId, params: browse.params)
    }

    private static func shelf(from section: BrowseResponse.SectionContent) -> HomeShelf? {
        if let grid = section.gridRenderer {
            return makeShelf(title: grid.title, contents: grid.items)
        }
        if let carousel = section.carousel {
            return makeShelf(title: carousel.title, contents: carousel.contents)
        }
        if let listShelf = section.listShelf {
            return makeShelf(title: listShelf.title?.text ?? "", contents: listShelf.contents)
        }
        return nil
    }

    private static func makeShelf(title: String, contents: [CarouselItem]?) -> HomeShelf? {
        let items = playableItems(contents)
        guard !items.isEmpty else { return nil }
        return HomeShelf(title: title.isEmpty ? "Library" : title, items: items)
    }

    /// Drops action tiles ("New playlist", "Shuffle all", "Add podcast") that
    /// neither play nor open a page.
    private static func playableItems(_ contents: [CarouselItem]?) -> [HomeItem] {
        (contents ?? [])
            .compactMap { HomeFeedParser.makeItem(from: $0) }
            .filter { $0.videoId != nil || $0.browseId != nil }
    }
}
