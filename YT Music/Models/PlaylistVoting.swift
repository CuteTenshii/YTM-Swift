//
//  PlaylistVoting.swift
//  YT Music
//

import Foundation

/// A playlist row's up/down votes, on playlists with voting turned on.
nonisolated struct PlaylistItemVote: Sendable, Equatable, Hashable {
    enum Status: Sendable, Hashable {
        case none
        case up
        case down
    }

    var status: Status
    /// The count to show in each status, as formatted by the server ("1.2K").
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

    /// The `feedback` token that moves this row's vote from `status` to `target`.
    /// Voting the other way replaces the existing vote.
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

/// One choice in an owned playlist's "Voting" setting.
nonisolated struct PlaylistVoteOption: Sendable, Equatable, Hashable, Identifiable {
    /// The `itemVotePermission` sent to change the setting.
    var value: Int
    var title: String
    var detail: String
    /// "Collaborators only" is unavailable while collaboration is off.
    var isDisabled: Bool
    var isSelected: Bool

    var id: Int { value }
}

/// The `edit_playlist` action behind one of an owned playlist's sort choices.
/// Unlike other playlists' sorts, it changes the playlist's saved order.
nonisolated struct PlaylistSortEdit: Sendable, Equatable, Hashable {
    var action: String
    var field: String
    var value: Int
    var params: String?
}
