//
//  PlaylistCollaboration.swift
//  YT Music
//

import Foundation

nonisolated struct CollaborationPanelRef: Sendable, Equatable {
    var panelId: String
    var params: String
}

nonisolated struct PlaylistCollaboration: Sendable, Equatable {
    var isEnabled: Bool
    var allowsNewCollaborators: Bool
    var inviteURL: URL?
    var collaborators: [PlaylistCollaborator]
}

nonisolated struct PlaylistCollaborator: Sendable, Equatable, Hashable {
    var name: String
    var role: String
    var avatarURL: URL?
    var link: EntityLink?
}
