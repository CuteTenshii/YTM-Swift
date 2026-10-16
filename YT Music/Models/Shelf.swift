//
//  Shelf.swift
//  YT Music
//
//  A titled, horizontally scrolling group of items. Shared by every page that
//  lays content out in shelves (home, explore, library, uploads, search, entity
//  pages and the related panel).
//

import Foundation

/// One horizontal carousel, e.g. "Listen again" or "Mixed for you".
struct Shelf: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var items: [ShelfItem]
    /// Tappable actions in the shelf header ("More", "Play all", …), parsed from
    /// the shelf's header buttons. Empty when the shelf carries none.
    var buttons: [ShelfButton] = []
    /// Rows stacked per column when YouTube lays the shelf out as a grid.
    var rowsPerColumn = 1
    /// Small label above the title, shown with `avatarURL` (the account on "Listen again").
    var strapline = ""
    var avatarURL: URL? = nil

    /// A chart shelf, whose rows carry a rank.
    var isRanked: Bool { items.contains { $0.chartRank != nil } }

    /// Rows per column for a grid of list rows, nil for a strip of cards.
    var gridRows: Int? {
        if rowsPerColumn > 1 { return rowsPerColumn }
        return isRanked ? 4 : nil
    }
}

/// A tappable action in a shelf header. YouTube shelves carry buttons beside the
/// title — a "More" link to a fuller listing, or a "Play all"-style play button.
struct ShelfButton: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var action: Action

    enum Action: Sendable, Hashable {
        /// Push a page (e.g. "More" → all of an artist's albums, a feed page).
        case navigate(EntityDestination)
        /// Play a playlist/album watch queue ("Play all"), optionally seeded at a
        /// specific video within it.
        case play(videoId: String?, playlistId: String)
    }
}
