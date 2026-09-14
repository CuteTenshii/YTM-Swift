//
//  Playlist.swift
//  YT Music
//
//  View-facing model for a playlist the signed-in user can edit — used to
//  populate the "Add to Playlist" picker and the lightweight playlist manager.
//

import Foundation

/// A playlist in the signed-in user's library that can be added to / renamed /
/// deleted. `id` is the raw InnerTube playlist id (e.g. "PL…", "LM"), suitable
/// for the `edit_playlist` / `playlist/delete` endpoints.
struct EditablePlaylist: Identifiable, Sendable, Equatable {
    let id: String
    var title: String
    var subtitle: String
    var thumbnailURL: URL?
}

extension String {
    /// Whether this raw playlist id names a system playlist — "Liked Music"
    /// (`LM`) and saved podcast episodes (`SE`) — which carry playlist-shaped
    /// data (even row `setVideoId`s) but reject edits: likes are managed
    /// per-track, and podcast saves aren't playlist membership.
    var isSystemPlaylistId: Bool { self == "LM" || self == "SE" }
}
