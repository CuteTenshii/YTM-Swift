//
//  HomeFeed.swift
//  YT Music
//
//  Clean, view-facing domain models for the Home feed. These are decoupled
//  from the raw InnerTube response shapes (see InnerTube/BrowseResponse.swift).
//

import Foundation

/// The whole home page: an ordered list of horizontal shelves.
struct HomeFeed: Sendable {
    var shelves: [Shelf]
    var chips: [FeedChip] = []
    /// Token for the next batch of shelves, nil once the feed is exhausted.
    var continuation: String? = nil
    /// The visitor id the continuation must be requested with.
    var visitorData: String? = nil
}
