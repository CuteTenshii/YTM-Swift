//
//  CommentsViewModel.swift
//  YT Music
//

import SwiftUI

@MainActor
@Observable
final class CommentsViewModel {
    enum State {
        case idle
        case loading
        case loaded
        case unavailable
        case failed(String)
    }

    private(set) var state: State = .idle
    /// The accumulated top-level comments (grows as more pages load).
    private(set) var comments: [Comment] = []
    /// True while a further page is being appended (infinite scroll).
    private(set) var isLoadingMore = false

    /// True once we've determined the current track has no comments (so the
    /// Comments tab/button can be disabled). False while idle/loading/loaded.
    var isUnavailable: Bool {
        if case .unavailable = state { return true }
        return false
    }

    /// Whether another page of comments can be loaded.
    var canLoadMore: Bool { nextToken != nil }

    private let client: CommentsProviding
    private var nextToken: String?
    /// The track a load is for, so a slower response for a previous track is
    /// discarded rather than shown over the current one.
    private var currentVideoId: String?

    init(client: CommentsProviding = InnerTubeClient.shared) {
        self.client = client
    }

    /// Loads the first page of comments for the given track. A nil id (nothing
    /// playing), or a track with no comments, resolves to `.unavailable`.
    func load(videoId: String?) async {
        guard let videoId else {
            reset(); state = .unavailable; return
        }
        currentVideoId = videoId
        reset()
        state = .loading
        do {
            let page = try await client.comments(for: videoId)
            guard currentVideoId == videoId else { return }
            comments = page.comments
            nextToken = page.continuationToken
            state = page.comments.isEmpty ? .unavailable : .loaded
        } catch {
            guard currentVideoId == videoId else { return }
            state = .failed(error.localizedDescription)
        }
    }

    /// Appends the next page of comments (called when the list nears its end).
    func loadMore() async {
        guard let token = nextToken, !isLoadingMore else { return }
        let videoId = currentVideoId
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await client.moreComments(token: token),
              currentVideoId == videoId else { return }
        comments.append(contentsOf: page.comments)
        nextToken = page.continuationToken
    }

    /// Loads a page of replies for a comment thread. Pass the previous page's
    /// token to page further; nil starts from the comment's own reply token.
    /// Returns the replies and the token for the next page (nil at the end).
    func replyPage(for comment: Comment, after token: String?) async -> (replies: [Comment], next: String?) {
        guard let token = token ?? comment.replyToken else { return ([], nil) }
        guard let page = try? await client.commentReplies(token: token, parentId: comment.id) else {
            return ([], nil)
        }
        return (page.comments, page.continuationToken)
    }

    private func reset() {
        comments = []
        nextToken = nil
        isLoadingMore = false
    }
}
