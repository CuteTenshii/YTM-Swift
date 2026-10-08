//
//  PlaylistCollaboration.swift
//  YT Music
//

import Foundation

/// The `get_panel` request that loads a playlist's collaboration settings.
nonisolated struct CollaborationPanelRef: Sendable, Equatable {
    var panelId: String
    var params: String
}

/// One of the user's playlists' collaboration state.
nonisolated struct PlaylistCollaboration: Sendable, Equatable {
    var isEnabled: Bool
    var allowsNewCollaborators: Bool
    /// The link that lets someone join. Nil while new collaborators aren't allowed.
    var inviteURL: URL?
    var collaborators: [PlaylistCollaborator]
}

nonisolated struct PlaylistCollaborator: Sendable, Equatable, Hashable {
    var name: String
    /// "Owner" for the playlist's owner, else empty.
    var role: String
    var avatarURL: URL?
    /// The collaborator's channel page.
    var link: EntityLink?
}
