//
//  PlayerState.swift
//  YT Music
//
//  App-wide playback state. Resolves a track's stream URL (via StreamResolver)
//  and drives an AudioPlayer, exposing what the now-playing UI needs.
//

import SwiftUI

/// Supplies an endless radio queue for a seed video. Abstracted so PlayerState
/// can be driven by a fake in tests (no network).
protocol RadioProviding: Sendable {
    func radio(for videoId: String) async throws -> [Track]
}

extension InnerTubeClient: RadioProviding {}

@MainActor
@Observable
final class PlayerState {
    struct NowPlaying: Equatable, Codable {
        var title: String
        var subtitle: String
        var album: String
        var thumbnailURL: URL?
        var videoId: String
    }

    /// How playback continues at the end of a track.
    enum RepeatMode: String, Codable {
        case off   // stop at the end of the queue
        case all   // loop the whole queue
        case one   // loop the current track
    }

    private(set) var nowPlaying: NowPlaying?
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var repeatMode: RepeatMode = .off

    /// The playable tracks (those with a videoId) for the current context, and
    /// the index within it that is currently playing. Empty for one-off plays.
    private(set) var queue: [Track] = []
    private(set) var currentIndex = 0
    private var albumContext = ""

    private let audio: AudioOutput
    private let resolver: StreamResolving
    private let radioProvider: RadioProviding
    private let store: PlaybackStore?
    private var loadTask: Task<Void, Never>?
    private var radioTask: Task<Void, Never>?
    /// True after restoring a snapshot until the user actually starts playback:
    /// the track is shown but no stream is loaded yet, so the first play resolves
    /// and starts it rather than toggling an empty engine.
    private var awaitingResume = false

    init(audio: AudioOutput? = nil, resolver: StreamResolving? = nil,
         radioProvider: RadioProviding? = nil, store: PlaybackStore? = nil) {
        self.audio = audio ?? AudioPlayer()
        self.resolver = resolver ?? StreamResolver.shared
        self.radioProvider = radioProvider ?? InnerTubeClient.shared
        self.store = store

        self.audio.onTrackFinished = { [weak self] in self?.handleTrackFinished() }
        self.audio.onNext = { [weak self] in self?.next() }
        self.audio.onPrevious = { [weak self] in self?.previous() }

        restore()
    }

    // MARK: - Playback intent

    /// Plays a single track with no surrounding queue (next/previous become no-ops).
    func play(title: String, subtitle: String, album: String = "", thumbnailURL: URL?, videoId: String) {
        queue = []
        currentIndex = 0
        startTrack(title: title, subtitle: subtitle, album: album,
                   thumbnailURL: thumbnailURL, videoId: videoId)
    }

    func play(_ track: Track, album: String = "") {
        guard let videoId = track.videoId else { return }
        play(
            title: track.title,
            subtitle: track.subtitle,
            album: album,
            thumbnailURL: track.thumbnailURL,
            videoId: videoId
        )
    }

    /// Plays `tracks` as a queue, starting at the track at `startAt` (an index
    /// into `tracks`). Unplayable tracks (no videoId) are filtered out; if the
    /// requested track isn't playable, the next playable one is used.
    func play(_ tracks: [Track], startAt: Int, album: String = "") {
        let playable = tracks.filter { $0.videoId != nil }
        guard !playable.isEmpty else { return }

        // Map the requested position to the filtered queue: the requested track,
        // else the first playable track at or after it, else the first overall.
        let startTrack = (startAt..<tracks.count).lazy
            .map { tracks[$0] }
            .first { $0.videoId != nil }
        let index = startTrack
            .flatMap { target in playable.firstIndex { $0.id == target.id } } ?? 0

        queue = playable
        albumContext = album
        currentIndex = index
        startCurrent()
    }

    /// "Start radio": plays the seed track immediately, then fetches an endless
    /// radio queue from it and installs that as the queue (so next/previous walk
    /// the radio) without interrupting the already-playing seed.
    func startRadio(title: String, subtitle: String, thumbnailURL: URL?, videoId: String) {
        play(title: title, subtitle: subtitle, thumbnailURL: thumbnailURL, videoId: videoId)
        radioTask?.cancel()
        radioTask = Task { await installRadio(seed: videoId) }
    }

    /// Fetches the radio queue for `videoId` and installs it (keeping the seed
    /// playing). Split out from `startRadio` so tests can await it directly.
    func installRadio(seed videoId: String) async {
        guard let tracks = try? await radioProvider.radio(for: videoId) else { return }
        let playable = tracks.filter { $0.videoId != nil }
        // Only install if the user is still on the seed track.
        guard !playable.isEmpty, nowPlaying?.videoId == videoId else { return }
        queue = playable
        albumContext = ""
        currentIndex = playable.firstIndex { $0.videoId == videoId } ?? 0
        persist()
    }

    // MARK: - Transport

    var isPlaying: Bool { audio.isPlaying }
    var currentTime: Double { audio.currentTime }
    var duration: Double { audio.duration }

    var canGoNext: Bool { !queue.isEmpty && (currentIndex + 1 < queue.count || repeatMode == .all) }
    var canGoPrevious: Bool { !queue.isEmpty && (currentIndex > 0 || repeatMode == .all) }

    func togglePlayPause() {
        // A track restored from a previous session isn't loaded yet — the first
        // play resolves and starts it.
        if awaitingResume {
            resumeRestored()
            return
        }
        audio.togglePlayPause()
    }
    func seek(to seconds: Double) { audio.seek(to: seconds) }

    func next() {
        guard !queue.isEmpty else { return }
        if currentIndex + 1 < queue.count {
            currentIndex += 1
        } else if repeatMode == .all {
            currentIndex = 0
        } else {
            return
        }
        startCurrent()
    }

    func previous() {
        // Match the common player behaviour: restart the current track if we're
        // more than a few seconds in, otherwise step back.
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        if currentIndex > 0 {
            currentIndex -= 1
        } else if repeatMode == .all {
            currentIndex = queue.count - 1
        } else {
            seek(to: 0)
            return
        }
        startCurrent()
    }

    func cycleRepeatMode() {
        repeatMode = switch repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
        persist()
    }

    private func handleTrackFinished() {
        switch repeatMode {
        case .one:        audio.restart()
        case .off, .all:  next()   // next() only wraps when .all; otherwise stops
        }
    }

    // MARK: - Persistence

    /// Loads the last session's snapshot into a paused, ready-to-resume state.
    private func restore() {
        guard let snapshot = store?.load() else { return }
        nowPlaying = snapshot.nowPlaying
        queue = snapshot.tracks.map(\.track)
        currentIndex = queue.isEmpty ? 0 : min(max(0, snapshot.currentIndex), queue.count - 1)
        repeatMode = snapshot.repeatMode
        albumContext = snapshot.album
        awaitingResume = true
    }

    private func persist() {
        guard let store else { return }
        guard let nowPlaying else { store.save(nil); return }
        store.save(PersistedPlayback(
            nowPlaying: nowPlaying,
            tracks: queue.map(PersistedPlayback.StoredTrack.init),
            currentIndex: currentIndex,
            repeatMode: repeatMode,
            album: albumContext
        ))
    }

    /// Starts the restored track (resolving its stream for the first time).
    private func resumeRestored() {
        if !queue.isEmpty {
            startCurrent()
        } else if let nowPlaying {
            startTrack(title: nowPlaying.title, subtitle: nowPlaying.subtitle,
                       album: nowPlaying.album, thumbnailURL: nowPlaying.thumbnailURL,
                       videoId: nowPlaying.videoId)
        }
    }

    // MARK: - Loading

    private func startCurrent() {
        guard queue.indices.contains(currentIndex),
              let videoId = queue[currentIndex].videoId else { return }
        let track = queue[currentIndex]
        startTrack(title: track.title, subtitle: track.subtitle, album: albumContext,
                   thumbnailURL: track.thumbnailURL, videoId: videoId)
    }

    private func startTrack(title: String, subtitle: String, album: String,
                            thumbnailURL: URL?, videoId: String) {
        awaitingResume = false
        nowPlaying = NowPlaying(
            title: title,
            subtitle: subtitle,
            album: album,
            thumbnailURL: thumbnailURL,
            videoId: videoId
        )
        loadError = nil
        isLoading = true
        persist()

        loadTask?.cancel()
        loadTask = Task { await loadStream(videoId: videoId) }
    }

    /// Resolves the stream and hands it to the audio engine. Split out from
    /// `startTrack` so tests can await it directly (no Task race).
    func loadStream(videoId: String) async {
        do {
            let resolved = try await resolver.audioStream(videoId: videoId)
            if Task.isCancelled { return }
            let metadata = NowPlayingMetadata(
                title: nowPlaying?.title ?? "",
                artist: Self.cleanedArtist(nowPlaying?.subtitle ?? ""),
                album: nowPlaying?.album ?? "",
                artworkURL: nowPlaying?.thumbnailURL,
                knownDuration: resolved.duration
            )
            audio.load(url: resolved.url, metadata: metadata)
        } catch {
            if !Task.isCancelled { loadError = error.localizedDescription }
        }
        if !Task.isCancelled { isLoading = false }
    }

    /// YT Music subtitles often lead with a content-type label
    /// ("Song • Artist • Album"); drop it so the Now Playing artist is the artist.
    private static func cleanedArtist(_ subtitle: String) -> String {
        for label in ["Song", "Video", "Episode", "Podcast"] {
            let prefix = "\(label) • "
            if subtitle.hasPrefix(prefix) {
                return String(subtitle.dropFirst(prefix.count))
            }
        }
        return subtitle
    }
}
