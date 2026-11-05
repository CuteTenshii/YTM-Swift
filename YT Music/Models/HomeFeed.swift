//
//  HomeFeed.swift
//  YT Music
//
//  Clean, view-facing domain models for the Home feed. These are decoupled
//  from the raw InnerTube response shapes (see InnerTube/BrowseResponse.swift).
//

import Foundation

struct HomeFeed: Sendable {
    var shelves: [Shelf]
    var chips: [FeedChip] = []
    var continuation: String? = nil
    var visitorData: String? = nil
}
