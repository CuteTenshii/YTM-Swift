//
//  SearchResults.swift
//  YT Music
//

import Foundation

nonisolated struct SearchResults: Sendable {
    var topResult: SearchTopResult?
    var shelves: [Shelf]

    var isEmpty: Bool { topResult == nil && shelves.isEmpty }
}

nonisolated struct SearchTopResult: Sendable {
    enum Action: Sendable, Hashable {
        case play(videoId: String?, playlistId: String?)
        case shuffle(playlistId: String)
        case mix(playlistId: String)
    }

    var item: ShelfItem
    var actions: [Action]
    var tracks: [ShelfItem]
}
