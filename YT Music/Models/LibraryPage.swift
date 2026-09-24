//
//  LibraryPage.swift
//  YT Music
//

import Foundation

/// One page of a library listing: the landing page or a chip's (Playlists,
/// Songs, …) page, or a continuation of either.
struct LibraryPage: Sendable {
    var shelves: [HomeShelf]
    /// Song listings, as playlist-style track rows.
    var tracks: [Track] = []
    /// The filter chips in the page header; empty for continuations.
    var chips: [HomeChip] = []
    var continuation: String?

    var isEmpty: Bool { shelves.allSatisfy(\.items.isEmpty) && tracks.isEmpty }

    /// This listing extended by its next page: cards join the last shelf,
    /// tracks are renumbered after the existing ones.
    func appending(_ next: LibraryPage) -> LibraryPage {
        var result = self
        let items = next.shelves.flatMap(\.items)
        if result.shelves.isEmpty {
            result.shelves = next.shelves
        } else {
            result.shelves[result.shelves.count - 1].items += items
        }
        result.tracks += next.tracks.enumerated().map { offset, track in
            var track = track
            track.index = tracks.count + offset + 1
            return track
        }
        result.continuation = next.continuation
        return result
    }
}
