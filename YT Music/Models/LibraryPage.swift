//
//  LibraryPage.swift
//  YT Music
//

import Foundation

struct LibraryPage: Sendable {
    var shelves: [Shelf]
    var tracks: [Track] = []
    var chips: [FeedChip] = []
    var continuation: String?

    var isEmpty: Bool { shelves.allSatisfy(\.items.isEmpty) && tracks.isEmpty }

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
