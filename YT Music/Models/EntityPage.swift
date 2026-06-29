//
//  EntityPage.swift
//  YT Music
//
//  View-facing models for an album / playlist / artist detail page, plus the
//  Hashable navigation value used to push one onto a NavigationStack.
//

import Foundation

/// Navigation value for pushing an entity detail page.
struct EntityDestination: Hashable {
    let browseId: String
    let kind: HomeItem.Kind
    /// Shown immediately (in the nav bar / header) while the page loads.
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
}

/// A fully-loaded album / playlist / artist page.
struct EntityPage: Sendable {
    var header: EntityHeader
    var tracks: [Track]
    var shelves: [HomeShelf]   // artist albums/singles/related, etc.
}

struct EntityHeader: Sendable {
    var title: String
    var subtitle: String       // e.g. "Album • Artist • 2020"
    var description: String
    var thumbnailURL: URL?
    var kind: HomeItem.Kind

    var prefersCircularArtwork: Bool { kind == .artist }
}

/// A single playable track in a listing.
struct Track: Identifiable, Sendable {
    let id = UUID()
    var index: Int             // 1-based position in its listing
    var title: String
    var subtitle: String       // artist(s)
    var duration: String?      // "3:45"
    var thumbnailURL: URL?
    var videoId: String?
}
