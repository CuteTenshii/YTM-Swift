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

    /// Codable mirror of `Track` (which carries a non-persisted UUID id).
    struct StoredTrack: Codable {
        var index: Int
        var title: String
        var subtitle: String
        var duration: String?
        var thumbnailURL: URL?
        var videoId: String?
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
            videoId: track.videoId
        )
    }

    var track: Track {
        Track(index: index, title: title, subtitle: subtitle,
              duration: duration, thumbnailURL: thumbnailURL, videoId: videoId)
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
