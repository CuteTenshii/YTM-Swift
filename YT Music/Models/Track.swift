//
//  Track.swift
//  YT Music
//
//  A single playable track in a listing, queue or now-playing context.
//

import Foundation

struct Track: Identifiable, Sendable {
    let id = UUID()
    var index: Int
    var title: String
    var subtitle: String
    var duration: String?
    var thumbnailURL: URL?
    var videoId: String?
    var artists: [EntityLink] = []
    var albumLink: EntityLink?
    var feedbackToken: String? = nil
    /// Plumbing only: any playlist's rows may carry one; `canRemoveFromPlaylist` is the permission signal.
    var playlistSetVideoId: String? = nil
    var canRemoveFromPlaylist: Bool = false
    var searchTerms: [String] = []
    var likeStatus: LikeStatus = .indifferent
    var vote: PlaylistItemVote? = nil
}
