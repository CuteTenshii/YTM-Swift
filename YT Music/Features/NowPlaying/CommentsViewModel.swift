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
    private(set) var comments: [Comment] = []
    private(set) var isLoadingMore = false

    var isUnavailable: Bool {
        if case .unavailable = state { return true }
        return false
    }

    var canLoadMore: Bool { nextToken != nil }

    private let client: CommentsProviding
    private var nextToken: String?
    private var currentVideoId: String?

    init(client: CommentsProviding = InnerTubeClient.shared) {
        self.client = client
    }

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
