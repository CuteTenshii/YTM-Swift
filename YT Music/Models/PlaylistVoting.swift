//
//  PlaylistVoting.swift
//  YT Music
//

import Foundation

nonisolated struct PlaylistItemVote: Sendable, Equatable, Hashable {
    enum Status: Sendable, Hashable {
        case none
        case up
        case down
    }

    var status: Status
    var neutralCount: String
    var upvotedCount: String
    var downvotedCount: String
    var upvoteToken: String
    var undoUpvoteToken: String
    var downvoteToken: String
    var undoDownvoteToken: String

    var count: String {
        switch status {
        case .none: neutralCount
        case .up: upvotedCount
        case .down: downvotedCount
        }
    }

    func token(toward target: Status) -> String? {
        switch (status, target) {
        case (.up, .none): undoUpvoteToken
        case (.down, .none): undoDownvoteToken
        case (_, .none): nil
        case (.up, .up), (.down, .down): nil
        case (_, .up): upvoteToken
        case (_, .down): downvoteToken
        }
    }
}

nonisolated struct PlaylistVoteOption: Sendable, Equatable, Hashable, Identifiable {
    var value: Int
    var title: String
    var detail: String
    /// "Collaborators only" is unavailable while collaboration is off.
    var isDisabled: Bool
    var isSelected: Bool

    var id: Int { value }
}

nonisolated struct PlaylistSortEdit: Sendable, Equatable, Hashable {
    var action: String
    var field: String
    var value: Int
    var params: String?
}
