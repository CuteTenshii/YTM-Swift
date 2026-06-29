//
//  LibraryFilter.swift
//  YT Music
//
//  The Library filter chips. Filtering is client-side over the already-loaded
//  shelves, by item kind.
//

import Foundation

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case playlists = "Playlists"
    case albums = "Albums"
    case artists = "Artists"
    case songs = "Songs"

    var id: Self { self }

    func matches(_ kind: HomeItem.Kind) -> Bool {
        switch self {
        case .all:       true
        case .playlists: kind == .playlist
        case .albums:    kind == .album
        case .artists:   kind == .artist
        case .songs:     kind == .song || kind == .video
        }
    }

    /// Keeps only items matching this chip, dropping shelves left empty.
    func apply(to shelves: [HomeShelf]) -> [HomeShelf] {
        guard self != .all else { return shelves }
        return shelves.compactMap { shelf in
            let items = shelf.items.filter { matches($0.kind) }
            return items.isEmpty ? nil : HomeShelf(title: shelf.title, items: items)
        }
    }

    /// Chips worth showing: `.all`, plus any category present in the shelves.
    static func available(for shelves: [HomeShelf]) -> [LibraryFilter] {
        let kinds = Set(shelves.flatMap { $0.items.map(\.kind) })
        return allCases.filter { $0 == .all || kinds.contains(where: $0.matches) }
    }
}
