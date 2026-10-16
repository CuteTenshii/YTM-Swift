//
//  FeedChip.swift
//  YT Music
//
//  A filter chip on a feed page (home, library): reloads the feed with its params.
//

import Foundation

struct FeedChip: Identifiable, Sendable, Hashable {
    let id: String
    var title: String
    var browseId: String
    var params: String?
}
