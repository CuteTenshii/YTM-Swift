//
//  PlaybackPersistence.swift
//  YT Music
//
//  Persists a snapshot of what's playing so the player can repopulate on the
//  next launch (the track appears in the now-playing bar, paused and ready to
//  resume). Backed by UserDefaults; abstracted behind a protocol so PlayerState
//  can be tested without touching real storage.
//

import Foundation

/// A snapshot of playback state, persisted across launches.
struct PersistedPlayback: Codable {
    var nowPlaying: PlayerState.NowPlaying
    var tracks: [StoredTrack]   // the queue (empty for a one-off play)
    var currentIndex: Int
    var repeatMode: PlayerState.RepeatMode
    var album: String
    var isShuffled: Bool = false
    /// The playlist the queue was started from (attribution context), if any.
    var playlistId: String? = nil

    init(nowPlaying: PlayerState.NowPlaying, tracks: [StoredTrack], currentIndex: Int,
         repeatMode: PlayerState.RepeatMode, album: String, isShuffled: Bool = false,
         playlistId: String? = nil) {
        self.nowPlaying = nowPlaying
        self.tracks = tracks
        self.currentIndex = currentIndex
        self.repeatMode = repeatMode
        self.album = album
        self.isShuffled = isShuffled
        self.playlistId = playlistId
    }

    // Tolerant decode so snapshots saved before shuffle existed still restore
    // (the new key defaults to false rather than failing the whole restore).
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nowPlaying = try c.decode(PlayerState.NowPlaying.self, forKey: .nowPlaying)
        tracks = try c.decode([StoredTrack].self, forKey: .tracks)
        currentIndex = try c.decode(Int.self, forKey: .currentIndex)
        repeatMode = try c.decode(PlayerState.RepeatMode.self, forKey: .repeatMode)
        album = try c.decode(String.self, forKey: .album)
        isShuffled = try c.decodeIfPresent(Bool.self, forKey: .isShuffled) ?? false
        playlistId = try c.decodeIfPresent(String.self, forKey: .playlistId)
    }

    /// Codable mirror of `Track` (which carries a non-persisted UUID id).
    struct StoredTrack: Codable {
        var index: Int
        var title: String
        var subtitle: String
        var duration: String?
        var thumbnailURL: URL?
        var videoId: String?
        var artists: [EntityLink] = []
        var albumLink: EntityLink?

        init(index: Int, title: String, subtitle: String, duration: String?,
             thumbnailURL: URL?, videoId: String?, artists: [EntityLink] = [],
             albumLink: EntityLink? = nil) {
            self.index = index
            self.title = title
            self.subtitle = subtitle
            self.duration = duration
            self.thumbnailURL = thumbnailURL
            self.videoId = videoId
            self.artists = artists
            self.albumLink = albumLink
        }

        // Tolerant decode so snapshots saved before links existed still restore.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            index = try c.decode(Int.self, forKey: .index)
            title = try c.decode(String.self, forKey: .title)
            subtitle = try c.decode(String.self, forKey: .subtitle)
            duration = try c.decodeIfPresent(String.self, forKey: .duration)
            thumbnailURL = try c.decodeIfPresent(URL.self, forKey: .thumbnailURL)
            videoId = try c.decodeIfPresent(String.self, forKey: .videoId)
            artists = try c.decodeIfPresent([EntityLink].self, forKey: .artists) ?? []
            albumLink = try c.decodeIfPresent(EntityLink.self, forKey: .albumLink)
        }
    }
}

extension PersistedPlayback.StoredTrack {
    init(_ track: Track) {
        self.init(
            index: track.index,
            title: track.title,
            subtitle: track.subtitle,
            duration: track.duration,
            thumbnailURL: track.thumbnailURL,
            videoId: track.videoId,
            artists: track.artists,
            albumLink: track.albumLink
        )
    }

    var track: Track {
        Track(index: index, title: title, subtitle: subtitle,
              duration: duration, thumbnailURL: thumbnailURL, videoId: videoId,
              artists: artists, albumLink: albumLink)
    }
}

/// Loads / saves the last playback snapshot.
protocol PlaybackStore {
    func load() -> PersistedPlayback?
    func save(_ snapshot: PersistedPlayback?)
}

struct UserDefaultsPlaybackStore: PlaybackStore {
    private let key = "playback.snapshot.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PersistedPlayback? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PersistedPlayback.self, from: data)
    }

    func save(_ snapshot: PersistedPlayback?) {
        guard let snapshot else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }
}
