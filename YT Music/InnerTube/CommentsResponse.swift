//
//  CommentsResponse.swift
//  YT Music
//
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
    /// Content lives in frameworkUpdates; these renderers only correlate a commentId with its reply token.
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
        // A bare continuation item at the end of the list carries the "load more" token.
        let continuationItemRenderer: ReplyContinuation?
    }

    struct CommentThreadRenderer: Decodable {
        let commentViewModel: ViewModelWrapper?
        let replies: Replies?

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

        var replyToken: String? { continuationItemRenderer?.token }
    }

    struct ReplyContinuation: Decodable {
        let continuationEndpoint: CommentEndpoint?
        let button: ButtonWrapper?

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

// Comments are a YouTube surface; audio-only tracks often have no comments panel, so there is no token.
nonisolated enum CommentsParser {
    /// Matches the panel by id or header title so a description panel isn't mistaken for it.
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

    /// Replies (replyLevel > 0) are skipped.
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

    /// Excludes the parent comment (the reply feed sometimes re-includes it).
    static func parseReplies(_ response: CommentsResponse, excluding parentId: String) -> CommentPage {
        let mutations = response.frameworkUpdates?.entityBatchUpdate?.mutations ?? []
        let replies = mutations.compactMap { mutation -> Comment? in
            guard let payload = mutation.payload?.commentEntityPayload,
                  let comment = comment(from: payload), comment.id != parentId else { return nil }
            return comment
        }
        return CommentPage(comments: replies, continuationToken: nextPageToken(response))
    }

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
