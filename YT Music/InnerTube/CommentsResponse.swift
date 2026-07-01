//
//  CommentsResponse.swift
//  YT Music
//
//  Decodable models for YouTube comments, fetched through the InnerTube `next`
//  endpoint in two steps:
//
//    1. `next` with the videoId returns engagement panels; the comments panel
//       carries a continuation token (CommentsTokenResponse).
//    2. `next` with that token returns the comment threads. The actual comment
//       data lives in `frameworkUpdates.entityBatchUpdate.mutations[]` as
//       `commentEntityPayload` entities (YouTube's modern comment view-model
//       framing); we read those directly (CommentsResponse).
//
//  Note: comments are a YouTube (not YT Music) surface. Audio-only tracks often
//  have no comments panel under the WEB_REMIX client, in which case step 1
//  yields no token and the UI shows "no comments".
//

import Foundation

// MARK: - Step 1: the continuation token

nonisolated struct CommentsTokenResponse: Decodable {
    let engagementPanels: [EngagementPanel]?

    struct EngagementPanel: Decodable {
        let engagementPanelSectionListRenderer: PanelRenderer?
    }

    struct PanelRenderer: Decodable {
        let panelIdentifier: String?
        let targetId: String?
        let header: PanelHeader?
        let content: PanelContent?

        /// The comments continuation token buried in the panel's first section.
        var token: String? {
            (content?.sectionListRenderer?.contents ?? [])
                .compactMap { $0.itemSectionRenderer?.contents }
                .flatMap { $0 }
                .compactMap { $0.continuationItemRenderer?.continuationEndpoint?.continuationCommand?.token }
                .first
        }
    }

    struct PanelHeader: Decodable {
        let engagementPanelTitleHeaderRenderer: TitleHeader?
        struct TitleHeader: Decodable {
            let title: InnerTubeText?
        }
    }

    struct PanelContent: Decodable {
        let sectionListRenderer: SectionList?
    }

    struct SectionList: Decodable {
        let contents: [Section]?
    }

    struct Section: Decodable {
        let itemSectionRenderer: ItemSection?
    }

    struct ItemSection: Decodable {
        let contents: [Item]?
    }

    struct Item: Decodable {
        let continuationItemRenderer: ContinuationItem?
    }

    struct ContinuationItem: Decodable {
        let continuationEndpoint: ContinuationEndpoint?
    }

    struct ContinuationEndpoint: Decodable {
        let continuationCommand: ContinuationCommand?
    }

    struct ContinuationCommand: Decodable {
        let token: String?
    }
}

// MARK: - Step 2: the comment entities

nonisolated struct CommentsResponse: Decodable {
    let frameworkUpdates: FrameworkUpdates?
    /// Carries the comment threads (whose `replies` hold per-comment reply
    /// continuation tokens). The comment *content* lives in frameworkUpdates;
    /// these renderers correlate a commentId with its reply token.
    let onResponseReceivedEndpoints: [ReceivedEndpoint]?

    struct FrameworkUpdates: Decodable {
        let entityBatchUpdate: EntityBatchUpdate?
    }

    struct EntityBatchUpdate: Decodable {
        let mutations: [Mutation]?
    }

    struct Mutation: Decodable {
        let payload: Payload?
    }

    struct Payload: Decodable {
        let commentEntityPayload: CommentEntityPayload?
    }

    struct CommentEntityPayload: Decodable {
        let properties: Properties?
        let author: Author?
        let toolbar: Toolbar?
        let avatar: Avatar?
    }

    struct Properties: Decodable {
        let commentId: String?
        let content: Content?
        let publishedTime: String?
        /// 0 for a top-level comment; >0 for a reply.
        let replyLevel: Int?

        struct Content: Decodable { let content: String? }
    }

    struct Author: Decodable {
        let displayName: String?
        let channelId: String?
        let avatarThumbnailUrl: String?
        let isVerified: Bool?
    }

    struct Toolbar: Decodable {
        /// Display like count shown on the (unliked) button, e.g. "1.2K".
        let likeCountNotliked: String?
        let replyCount: String?
    }

    struct Avatar: Decodable {
        let image: AvatarImage?
        struct AvatarImage: Decodable {
            let sources: [Source]?
            struct Source: Decodable {
                let url: String?
                let width: Int?
            }
        }
    }

    // MARK: Comment threads (reply tokens)

    struct ReceivedEndpoint: Decodable {
        let reloadContinuationItemsCommand: ContinuationItems?
        let appendContinuationItemsAction: ContinuationItems?

        var items: [ThreadItem] {
            (reloadContinuationItemsCommand ?? appendContinuationItemsAction)?.continuationItems ?? []
        }
    }

    struct ContinuationItems: Decodable {
        let continuationItems: [ThreadItem]?
    }

    struct ThreadItem: Decodable {
        let commentThreadRenderer: CommentThreadRenderer?
        /// A bare continuation item (no thread) carries the "load more comments"
        /// paging token at the end of the list.
        let continuationItemRenderer: ReplyContinuation?
    }

    struct CommentThreadRenderer: Decodable {
        let commentViewModel: ViewModelWrapper?
        let replies: Replies?

        /// (commentId, replyToken) for this thread, when both are present.
        var replyToken: (id: String, token: String)? {
            guard let id = commentViewModel?.commentViewModel?.commentId,
                  let token = replies?.commentRepliesRenderer?.contents?
                    .lazy.compactMap(\.replyToken).first else { return nil }
            return (id, token)
        }
    }

    struct ViewModelWrapper: Decodable {
        let commentViewModel: ViewModel?
        struct ViewModel: Decodable { let commentId: String? }
    }

    struct Replies: Decodable {
        let commentRepliesRenderer: RepliesRenderer?
    }

    struct RepliesRenderer: Decodable {
        let contents: [ReplyContent]?
    }

    struct ReplyContent: Decodable {
        let continuationItemRenderer: ReplyContinuation?

        /// The reply continuation token, from either the plain continuation
        /// endpoint or the "View N replies" button.
        var replyToken: String? { continuationItemRenderer?.token }
    }

    struct ReplyContinuation: Decodable {
        let continuationEndpoint: CommentEndpoint?
        let button: ButtonWrapper?

        /// The token from either the plain continuation endpoint or a button
        /// ("View N replies" / "Show more").
        var token: String? {
            continuationEndpoint?.continuationCommand?.token
                ?? button?.buttonRenderer?.command?.continuationCommand?.token
        }

        struct ButtonWrapper: Decodable {
            let buttonRenderer: ButtonRenderer?
            struct ButtonRenderer: Decodable {
                let command: CommentEndpoint?
            }
        }
    }

    struct CommentEndpoint: Decodable {
        let continuationCommand: Command?
        struct Command: Decodable { let token: String? }
    }
}

// MARK: - Parser

nonisolated enum CommentsParser {
    /// The continuation token for the comments engagement panel, if present.
    /// Identifies the panel by its id or header title so a non-comments panel
    /// (e.g. a description panel) isn't mistaken for it.
    static func continuationToken(_ response: CommentsTokenResponse) -> String? {
        for panel in response.engagementPanels ?? [] {
            guard let renderer = panel.engagementPanelSectionListRenderer else { continue }
            let identity = (renderer.panelIdentifier ?? "") + " " + (renderer.targetId ?? "")
            let title = renderer.header?.engagementPanelTitleHeaderRenderer?.title?.text ?? ""
            let isComments = identity.localizedCaseInsensitiveContains("comment")
                || title.localizedCaseInsensitiveContains("comment")
            if isComments, let token = renderer.token { return token }
        }
        return nil
    }

    /// Flattens the comment entity mutations into top-level Comments (preserving
    /// the server's order, attaching each one's reply token) plus the paging
    /// token for the next page. Replies (replyLevel > 0) are skipped.
    static func parse(_ response: CommentsResponse) -> CommentPage {
        let tokens = replyTokens(response)
        let mutations = response.frameworkUpdates?.entityBatchUpdate?.mutations ?? []
        let comments = mutations.compactMap { mutation -> Comment? in
            guard let payload = mutation.payload?.commentEntityPayload,
                  (payload.properties?.replyLevel ?? 0) == 0,
                  var comment = comment(from: payload) else { return nil }
            comment.replyToken = tokens[comment.id]
            return comment
        }
        return CommentPage(comments: comments, continuationToken: nextPageToken(response))
    }

    /// Parses a reply continuation into a page of Comments, excluding the parent
    /// comment (the reply feed sometimes re-includes it), plus the paging token
    /// for more replies. No replyLevel filtering, since the feed is already
    /// scoped to one thread's replies.
    static func parseReplies(_ response: CommentsResponse, excluding parentId: String) -> CommentPage {
        let mutations = response.frameworkUpdates?.entityBatchUpdate?.mutations ?? []
        let replies = mutations.compactMap { mutation -> Comment? in
            guard let payload = mutation.payload?.commentEntityPayload,
                  let comment = comment(from: payload), comment.id != parentId else { return nil }
            return comment
        }
        return CommentPage(comments: replies, continuationToken: nextPageToken(response))
    }

    /// Builds a Comment from one entity payload (without a reply token).
    private static func comment(from payload: CommentsResponse.CommentEntityPayload) -> Comment? {
        guard let props = payload.properties,
              let id = props.commentId,
              let text = props.content?.content, !text.isEmpty else { return nil }

        let avatarURL = payload.avatar?.image?.sources?
            .max { ($0.width ?? 0) < ($1.width ?? 0) }?.url
            ?? payload.author?.avatarThumbnailUrl

        return Comment(
            id: id,
            author: payload.author?.displayName ?? "",
            authorThumbnailURL: avatarURL.flatMap { URL(string: $0) },
            text: text,
            likeCount: emptyToNil(payload.toolbar?.likeCountNotliked),
            publishedTime: props.publishedTime,
            isVerified: payload.author?.isVerified ?? false,
            replyCount: emptyToNil(payload.toolbar?.replyCount)
        )
    }

    /// Maps each comment id to its reply continuation token (only threads that
    /// actually have replies appear).
    private static func replyTokens(_ response: CommentsResponse) -> [String: String] {
        var map: [String: String] = [:]
        for endpoint in response.onResponseReceivedEndpoints ?? [] {
            for item in endpoint.items {
                if let pair = item.commentThreadRenderer?.replyToken {
                    map[pair.id] = pair.token
                }
            }
        }
        return map
    }

    /// The "load more" paging token — a trailing continuation item that isn't a
    /// comment thread — for the next page of the feed.
    private static func nextPageToken(_ response: CommentsResponse) -> String? {
        for endpoint in response.onResponseReceivedEndpoints ?? [] {
            for item in endpoint.items where item.commentThreadRenderer == nil {
                if let token = item.continuationItemRenderer?.token { return token }
            }
        }
        return nil
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value != "0" else { return nil }
        return value
    }
}
