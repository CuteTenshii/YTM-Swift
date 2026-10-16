//
//  Track.swift
//  YT Music
//
//  A single playable track in a listing, queue or now-playing context.
//

import Foundation

/// A single playable track in a listing.
struct Track: Identifiable, Sendable {
    let id = UUID()
    var index: Int             // 1-based position in its listing
    var title: String
    var subtitle: String       // artist(s)
    var duration: String?      // "3:45"
    var thumbnailURL: URL?
    var videoId: String?
    /// Navigable artist links parsed from the row, if any.
    var artists: [EntityLink] = []
    /// Navigable album link parsed from the row, if any.
    var albumLink: EntityLink?
    /// History-removal feedback token, when this track came from the history page.
    var feedbackToken: String? = nil
    /// Playlist-scoped id for removing this row from an owned playlist, if known.
    /// Note: this is plumbing, not permission — rows of *any* playlist may carry
    /// one. `canRemoveFromPlaylist` is the permission signal.
    var playlistSetVideoId: String? = nil
    /// The server's permission signal: this row's menu carried a
    /// remove-from-playlist action, which only rows of playlists the signed-in
    /// user can edit get. Gates both the row's "Remove from Playlist" entry
    /// and the page's edit affordances.
    var canRemoveFromPlaylist: Bool = false
    /// Additional text fields used by lightweight playlist search results.
    var searchTerms: [String] = []
    /// The account's current like rating for this track, parsed from the row's
    /// menu when available (signed in). `.indifferent` when unknown — enough for
    /// a context menu to show the right "Like" / "Remove from Likes" label.
    var likeStatus: LikeStatus = .indifferent
    /// Up/down votes, on playlists with voting turned on.
    var vote: PlaylistItemVote? = nil
}
