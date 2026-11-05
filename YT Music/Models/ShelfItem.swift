//
//  ShelfItem.swift
//  YT Music
//
//  A single card or row on a shelf: a song, album, playlist, artist or podcast.
//

import Foundation

struct ShelfItem: Identifiable, Sendable {
    enum Kind: Sendable, Hashable, Codable {
        case song
        case video
        case album
        case playlist
        case artist
        case profile
        case podcast
        case unknown
    }

    let id = UUID()
    var title: String
    var subtitle: String
    var thumbnailURL: URL?
    var kind: Kind

    var videoId: String?
    var browseId: String?
    var playlistId: String?

    var artists: [EntityLink] = []
    var albumLink: EntityLink?
    var deleteEntityId: String? = nil
    var likeStatus: LikeStatus? = nil
    var chartRank: ChartRank? = nil
    var editablePlaylistId: String? = nil

    var prefersCircularArtwork: Bool { kind == .artist || kind == .profile }

    var entityDestination: EntityDestination? {
        guard let browseId else { return nil }
        return EntityDestination(
            browseId: browseId,
            kind: kind,
            title: title,
            subtitle: subtitle,
            thumbnailURL: thumbnailURL
        )
    }
}

nonisolated struct ChartRank: Sendable, Hashable {
    enum Trend: Sendable, Hashable {
        case up, down, neutral

        init?(iconType: String) {
            switch iconType {
            case "ARROW_DROP_UP": self = .up
            case "ARROW_DROP_DOWN": self = .down
            case "ARROW_CHART_NEUTRAL": self = .neutral
            default: return nil
            }
        }
    }

    var rank: String
    var trend: Trend?
}
