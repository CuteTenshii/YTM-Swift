//
//  Comment.swift
//  YT Music
//
//  View-facing model for a top-level comment on the playing track, sourced from
//  YouTube's comment threads (the `next` endpoint's comments continuation).
//

import Foundation

/// A single top-level comment.
struct Comment: Identifiable, Hashable, Sendable {
    let id: String
    var author: String
    var authorThumbnailURL: URL?
    var text: String
    /// Display like count ("1.2K"), nil when zero/absent.
    var likeCount: String?
    /// Relative time ("2 years ago"), as served.
    var publishedTime: String?
    var isVerified: Bool
    /// Display reply count ("3"), nil when none.
    var replyCount: String?
    /// Continuation token for fetching this comment's replies, nil when none.
    var replyToken: String?
}

/// One page of comments (or replies): the items plus the continuation token for
/// the next page, if any. A nil token means the end of the feed.
struct CommentPage: Sendable {
    var comments: [Comment]
    var continuationToken: String?

    static let empty = CommentPage(comments: [], continuationToken: nil)
}
