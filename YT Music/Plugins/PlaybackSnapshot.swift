//
//  PlaybackSnapshot.swift
//  YT Music
//
//

import Foundation

struct PlaybackSnapshot: Sendable, Equatable {
    var title: String
    var artist: String
    var album: String
    var videoId: String
    var artists: [EntityLink] = []
    var albumLink: EntityLink? = nil
    var thumbnailURL: URL?
    var isPlaying: Bool
    var currentTime: Double
    var duration: Double
}
