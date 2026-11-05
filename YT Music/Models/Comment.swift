//
//  Comment.swift
//  YT Music
//
//  View-facing model for a top-level comment on the playing track, sourced from
//  YouTube's comment threads (the `next` endpoint's comments continuation).
//

import Foundation

struct Comment: Identifiable, Hashable, Sendable {
    let id: String
    var author: String
    var authorThumbnailURL: URL?
    var text: String
    var likeCount: String?
    var publishedTime: String?
    var isVerified: Bool
    var replyCount: String?
    var replyToken: String?
}

struct CommentPage: Sendable {
    var comments: [Comment]
    var continuationToken: String?

    static let empty = CommentPage(comments: [], continuationToken: nil)
}
