//
//  PlaybackSnapshot.swift
//  YT Music
//
//  A point-in-time, Sendable view of what's playing. PlayerState publishes one
//  on every track/playback-state change; plugins (Discord Rich Presence, the
//  downloader) consume it without reaching back into PlayerState.
//

import Foundation

struct PlaybackSnapshot: Sendable, Equatable {
    var title: String
    var artist: String
    var album: String
    var videoId: String
    var thumbnailURL: URL?
    var isPlaying: Bool
    var currentTime: Double
    var duration: Double
}
