//
//  Playlist.swift
//  YT Music
//
//  View-facing model for a playlist the signed-in user can edit, used to
//  populate the "Add to Playlist" picker and the lightweight playlist manager.
//

import Foundation

struct EditablePlaylist: Identifiable, Sendable, Equatable {
    let id: String
    var title: String
    var subtitle: String
    var thumbnailURL: URL?
}

extension String {
    /// System playlists (`LM`, `SE`) carry playlist-shaped data but reject edits.
    var isSystemPlaylistId: Bool { self == "LM" || self == "SE" }
}
