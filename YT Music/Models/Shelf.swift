//
//  Shelf.swift
//  YT Music
//
//  A titled, horizontally scrolling group of items. Shared by every page that
//  lays content out in shelves (home, explore, library, uploads, search, entity
//  pages and the related panel).
//

import Foundation

struct Shelf: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var items: [ShelfItem]
    var buttons: [ShelfButton] = []
    var rowsPerColumn = 1
    var strapline = ""
    var avatarURL: URL? = nil

    var isRanked: Bool { items.contains { $0.chartRank != nil } }

    var gridRows: Int? {
        if rowsPerColumn > 1 { return rowsPerColumn }
        return isRanked ? 4 : nil
    }
}

struct ShelfButton: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var action: Action

    enum Action: Sendable, Hashable {
        case navigate(EntityDestination)
        case play(videoId: String?, playlistId: String)
    }
}
