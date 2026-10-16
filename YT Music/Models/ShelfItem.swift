//
//  ShelfItem.swift
//  YT Music
//
//  A single card or row on a shelf: a song, album, playlist, artist or podcast.
//

import Foundation

/// A single card inside a shelf.
struct ShelfItem: Identifiable, Sendable {
    enum Kind: Sendable, Hashable, Codable {
        case song          // playable track
        case video         // music video
        case album
        case playlist
        case artist
        case profile       // a user's channel
        case podcast       // a podcast show
        case unknown
    }

    let id = UUID()
    var title: String
    var subtitle: String
    var thumbnailURL: URL?
    var kind: Kind

    /// Set for songs/videos — the watch endpoint target.
    var videoId: String?
    /// Set for albums/playlists/artists — the browse endpoint target.
    var browseId: String?
    /// Set for playlists/albums that can be queued.
    var playlistId: String?

    /// Navigable artist links parsed from the row's byline, if any. Lets cards /
    /// rows offer "Go to artist" and render clickable artist names.
    var artists: [EntityLink] = []
    /// Navigable album link parsed from the row's byline, if any.
    var albumLink: EntityLink?
    /// Delete entity id for an uploaded item (uploaded song/album), enabling a
    /// "Delete upload" action. nil for everything that isn't a user upload.
    var deleteEntityId: String? = nil
    /// The account's current like rating for a song row, parsed from its menu
    /// when signed in. `nil` when the row carried no like info at all (e.g. a
    /// feed-page card) — distinct from a known `.indifferent` — so the UI can
    /// decide whether to resolve it on demand.
    var likeStatus: LikeStatus? = nil
    /// Chart position for rows of a ranked shelf ("Top songs", "Trending").
    var chartRank: ChartRank? = nil
    /// The playlist id when this card is one of the user's own playlists (its
    /// menu offers "Edit playlist"), letting cards offer rename/delete with no
    /// page load.
    var editablePlaylistId: String? = nil

    /// Artists and profiles render as circles; everything else as rounded squares.
    var prefersCircularArtwork: Bool { kind == .artist || kind == .profile }

    /// A push destination if this item is a browsable page (album/playlist/
    /// artist/other browse), else nil (songs & videos play instead).
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

/// A row's position in a chart, with its movement since the last chart when known.
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
