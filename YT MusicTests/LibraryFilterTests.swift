//
//  LibraryFilterTests.swift
//  YT MusicTests
//

import Testing
@testable import YT_Music

@Suite("Library filter")
@MainActor
struct LibraryFilterTests {

    private func item(_ kind: HomeItem.Kind) -> HomeItem {
        HomeItem(title: "x", subtitle: "", thumbnailURL: nil, kind: kind,
                 videoId: nil, browseId: "b", playlistId: nil)
    }

    private var shelves: [HomeShelf] {
        [
            HomeShelf(title: "Mixed", items: [item(.playlist), item(.album), item(.artist)]),
            HomeShelf(title: "Albums", items: [item(.album)]),
        ]
    }

    @Test(".all returns everything unchanged")
    func allPassesThrough() {
        let result = LibraryFilter.all.apply(to: shelves)
        #expect(result.count == 2)
        #expect(result.flatMap(\.items).count == 4)
    }

    @Test("Filtering keeps only matching items and drops empty shelves")
    func filtersByKind() {
        let result = LibraryFilter.albums.apply(to: shelves)
        #expect(result.count == 2)                       // both shelves have an album
        #expect(result.flatMap(\.items).allSatisfy { $0.kind == .album })

        let artists = LibraryFilter.artists.apply(to: shelves)
        #expect(artists.count == 1)                      // only the "Mixed" shelf
        #expect(artists.first?.title == "Mixed")
    }

    @Test("Songs filter matches songs and videos")
    func songsMatchVideos() {
        #expect(LibraryFilter.songs.matches(.song))
        #expect(LibraryFilter.songs.matches(.video))
        #expect(!LibraryFilter.songs.matches(.album))
    }

    @Test("Available chips reflect present kinds, always starting with .all")
    func availableChips() {
        let available = LibraryFilter.available(for: shelves)
        #expect(available.first == .all)
        #expect(available.contains(.playlists))
        #expect(available.contains(.albums))
        #expect(available.contains(.artists))
        #expect(!available.contains(.songs))            // no songs present
    }

    @Test("No shelves yields just .all")
    func availableEmpty() {
        #expect(LibraryFilter.available(for: []) == [.all])
    }
}
