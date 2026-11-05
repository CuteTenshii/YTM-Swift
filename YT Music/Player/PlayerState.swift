//
//  PlayerState.swift
//  YT Music
//
//  App-wide playback state. Resolves a track's stream URL (via StreamResolver)
//  and drives an AudioPlayer, exposing what the now-playing UI needs.
//

import SwiftUI

/// A batch of a mix/radio plus a token for its next batch (nil when exhausted).
struct RadioPage: Sendable {
    let tracks: [Track]
    let continuation: String?
}

protocol RadioProviding: Sendable {
    func radio(for videoId: String) async throws -> RadioPage
    func continueRadio(_ token: String) async throws -> RadioPage
    func watchQueue(videoId: String, playlistId: String) async throws -> [Track]
}

extension RadioProviding {
    func watchQueue(videoId: String, playlistId: String) async throws -> [Track] {
        try await radio(for: videoId).tracks
    }
}

extension InnerTubeClient: RadioProviding {}

enum MixIds {
    /// A song's auto-generated radio: `RDAMVM<videoId>`.
    static func songRadio(for videoId: String) -> String { "RDAMVM\(videoId)" }
    /// A playlist's or album's radio: `RDAMPL<playlistId>`.
    static func playlistRadio(for playlistId: String) -> String { "RDAMPL\(playlistId)" }
}

@MainActor
@Observable
final class PlayerState {
    struct NowPlaying: Equatable, Codable {
        var title: String
        var subtitle: String
        var album: String
        var thumbnailURL: URL?
        var videoId: String
        var artists: [EntityLink] = []
        var albumLink: EntityLink?

        init(title: String, subtitle: String, album: String, thumbnailURL: URL?,
             videoId: String, artists: [EntityLink] = [], albumLink: EntityLink? = nil) {
            self.title = title
            self.subtitle = subtitle
            self.album = album
            self.thumbnailURL = thumbnailURL
            self.videoId = videoId
            self.artists = artists
            self.albumLink = albumLink
        }

        // Custom decode so older snapshots without links still load.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            subtitle = try c.decode(String.self, forKey: .subtitle)
            album = try c.decode(String.self, forKey: .album)
            thumbnailURL = try c.decodeIfPresent(URL.self, forKey: .thumbnailURL)
            videoId = try c.decode(String.self, forKey: .videoId)
            artists = try c.decodeIfPresent([EntityLink].self, forKey: .artists) ?? []
            albumLink = try c.decodeIfPresent(EntityLink.self, forKey: .albumLink)
        }
    }

    enum RepeatMode: String, Codable {
        case off
        case all
        case one
    }

    private(set) var nowPlaying: NowPlaying?
    private(set) var isLoading = false
    /// The stream is with the engine but not yet audible.
    private var awaitingAudio = false
    private(set) var loadError: String?
    private(set) var repeatMode: RepeatMode = .off
    private(set) var isEpisode = false
    /// How the current track's stream was chosen; may lag `nowPlaying` while a track loads.
    private(set) var streamDetails: StreamDetails?
    static let skipBackSeconds: Double = 15
    static let skipForwardSeconds: Double = 30
    static let playbackRates: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2]
    /// Speed for episodes; music always plays at 1x.
    var playbackRate: Double = 1 {
        didSet {
            settings?.podcastPlaybackRate = playbackRate
            applyPlaybackRate()
        }
    }
    private(set) var isShuffled = false
    private var orderBeforeShuffle: [Track] = []

    /// Seeded to `.indifferent`, then refreshed from the server.
    private(set) var likeStatus: LikeStatus = .indifferent
    private(set) var likeCount: Int?
    private(set) var isUpdatingLike = false
    /// Set when the user toggles like, so a slower status fetch doesn't overwrite it.
    private var likeInteracted = false
    /// Ratings of non-current tracks by videoId; the current track's `likeStatus` wins.
    private var likeStatusCache: [String: LikeStatus] = [:]

    private(set) var queue: [Track] = []
    private(set) var currentIndex = 0
    private var albumContext = ""
    private var playlistContext: String?
    private var radioContinuation: String?

    private let audio: AudioOutput
    private let resolver: StreamResolving
    private let radioProvider: RadioProviding
    private let likeProvider: LikeProviding
    private let historyReporter: WatchHistoryReporting
    private let store: PlaybackStore?
    private let settings: AppSettings?
    private let handoff = Handoff()
    private var loadTask: Task<Void, Never>?
    private var radioTask: Task<Void, Never>?
    private var likeFetchTask: Task<Void, Never>?
    /// After restore until first play: track shown, no stream loaded.
    private var awaitingResume = false
    private var restoredPosition: Double = 0
    private var restoredDuration: Double = 0
    private var lastPersistedPosition: Double = 0
    /// Set once per track when a crossfade is armed; re-armed when a new track starts.
    private var crossfadeArmed = false
    /// True from arming a crossfade until the incoming track takes over.
    private(set) var crossfadeLoading = false
    private var preparedVideoId: String?
    private var preparedStream: ResolvedStream?
    private var preloadTask: Task<Void, Never>?

    private var pendingHistory: ResolvedStream?
    private var playbackPinged = false
    private var lastWatchtimeAt: Double = -1

    var onPlaybackChange: ((PlaybackSnapshot?) -> Void)?
    var onPlaybackProgress: ((Double, Double) -> Void)?

    var spectrum: SpectrumAnalyzer? { audio.spectrum }

    init(audio: AudioOutput? = nil, resolver: StreamResolving? = nil,
         radioProvider: RadioProviding? = nil, store: PlaybackStore? = nil,
         settings: AppSettings? = nil, historyReporter: WatchHistoryReporting? = nil,
         likeProvider: LikeProviding? = nil) {
        self.audio = audio ?? AudioPlayer()
        self.level = self.audio.volume
        self.resolver = resolver ?? StreamResolver.shared
        self.radioProvider = radioProvider ?? InnerTubeClient.shared
        self.likeProvider = likeProvider ?? InnerTubeClient.shared
        self.historyReporter = historyReporter ?? InnerTubeClient.shared
        self.store = store
        self.settings = settings

        self.audio.onTrackFinished = { [weak self] in self?.handleTrackFinished() }
        self.audio.onNext = { [weak self] in self?.next() }
        self.audio.onPrevious = { [weak self] in self?.previous() }
        self.audio.onTogglePlayPause = { [weak self] in self?.togglePlayPause() }
        self.audio.onPlaybackStart = { [weak self] in self?.handlePlaybackStart() }
        self.audio.onProgress = { [weak self] current, duration in
            self?.handleProgress(current: current, duration: duration)
        }

        if let settings {
            self.audio.applyEqualizer(settings.equalizerSettings)
            settings.onEqualizerChange = { [weak self] eq in self?.audio.applyEqualizer(eq) }
            self.level = settings.volume
            self.isMuted = settings.isMuted
            self.audio.volume = isMuted ? 0 : level
            self.playbackRate = settings.podcastPlaybackRate
            self.audio.normalizesVolume = settings.volumeNormalization
            settings.onVolumeNormalizationChange = { [weak self] in self?.audio.normalizesVolume = $0 }
        }

        restore()
    }

    // MARK: - Playback intent

    func play(title: String, subtitle: String, album: String = "", thumbnailURL: URL?, videoId: String,
              artists: [EntityLink] = [], albumLink: EntityLink? = nil) {
        queue = []
        currentIndex = 0
        albumContext = ""
        playlistContext = nil
        radioContinuation = nil
        resetShuffle()
        startTrack(title: title, subtitle: subtitle, album: album,
                   thumbnailURL: thumbnailURL, videoId: videoId,
                   artists: artists, albumLink: albumLink)
    }

    func play(_ track: Track, album: String = "") {
        guard let videoId = track.videoId else { return }
        play(
            title: track.title,
            subtitle: track.subtitle,
            album: album,
            thumbnailURL: track.thumbnailURL,
            videoId: videoId,
            artists: track.artists,
            albumLink: track.albumLink
        )
    }

    func play(_ tracks: [Track], startAt: Int, album: String = "", playlistId: String? = nil) {
        let playable = tracks.filter { $0.videoId != nil }
        guard !playable.isEmpty else { return }

        let startTrack = (startAt..<tracks.count).lazy
            .map { tracks[$0] }
            .first { $0.videoId != nil }
        let index = startTrack
            .flatMap { target in playable.firstIndex { $0.id == target.id } } ?? 0

        queue = playable
        albumContext = album
        playlistContext = playlistId
        currentIndex = index
        radioContinuation = nil
        resetShuffle()
        startCurrent()
    }

    func playNext(title: String, subtitle: String, thumbnailURL: URL?, videoId: String,
                  artists: [EntityLink] = [], albumLink: EntityLink? = nil) {
        guard let nowPlaying else {
            play(title: title, subtitle: subtitle, thumbnailURL: thumbnailURL, videoId: videoId,
                 artists: artists, albumLink: albumLink)
            return
        }

        let track = Track(index: 0, title: title, subtitle: subtitle, duration: nil,
                          thumbnailURL: thumbnailURL, videoId: videoId,
                          artists: artists, albumLink: albumLink)

        if queue.isEmpty {
            let seedTrack = Track(index: 1, title: nowPlaying.title, subtitle: nowPlaying.subtitle,
                                  duration: nil, thumbnailURL: nowPlaying.thumbnailURL,
                                  videoId: nowPlaying.videoId, artists: nowPlaying.artists,
                                  albumLink: nowPlaying.albumLink)
            queue = [seedTrack, track]
            currentIndex = 0
        } else {
            queue.insert(track, at: currentIndex + 1)
        }
        persist()
    }

    func startRadio(title: String, subtitle: String, thumbnailURL: URL?, videoId: String,
                    artists: [EntityLink] = [], albumLink: EntityLink? = nil) {
        if nowPlaying?.videoId != videoId {
            play(title: title, subtitle: subtitle, thumbnailURL: thumbnailURL, videoId: videoId,
                 artists: artists, albumLink: albumLink)
        }
        radioTask?.cancel()
        radioTask = Task { await installRadio(seed: videoId) }
    }

    func installRadio(seed videoId: String) async {
        guard let page = try? await radioProvider.radio(for: videoId) else { return }
        let playable = page.tracks.filter { $0.videoId != nil }
        // Only install if the user is still on the seed track.
        guard !playable.isEmpty, let nowPlaying, nowPlaying.videoId == videoId else { return }
        radioContinuation = page.continuation
        playlistContext = MixIds.songRadio(for: videoId)
        if let index = playable.firstIndex(where: { $0.videoId == videoId }) {
            queue = playable
            currentIndex = index
        } else {
            // Some radio responses omit the seed; keep it as head so the current row matches.
            let seedTrack = Track(index: 1, title: nowPlaying.title, subtitle: nowPlaying.subtitle,
                                  duration: nil, thumbnailURL: nowPlaying.thumbnailURL, videoId: videoId,
                                  artists: nowPlaying.artists, albumLink: nowPlaying.albumLink)
            queue = [seedTrack] + playable
            currentIndex = 0
        }
        albumContext = ""
        resetShuffle()
        persist()
    }

    func playAll(videoId: String?, playlistId: String, shuffled: Bool = false) {
        loadTask?.cancel()
        radioTask?.cancel()
        radioTask = Task { await loadAndPlayAll(videoId: videoId, playlistId: playlistId, shuffled: shuffled) }
    }

    func loadAndPlayAll(videoId: String?, playlistId: String, shuffled: Bool = false) async {
        guard let tracks = try? await radioProvider.watchQueue(videoId: videoId ?? "", playlistId: playlistId),
              !tracks.isEmpty else { return }
        let start = shuffled
            ? Int.random(in: tracks.indices)
            : videoId.flatMap { id in tracks.firstIndex { $0.videoId == id } } ?? 0
        play(tracks, startAt: start, playlistId: playlistId)
        if shuffled { toggleShuffle() }
    }

    func enqueueAll(playlistId: String, next: Bool) {
        Task { await loadAndEnqueueAll(playlistId: playlistId, next: next) }
    }

    func loadAndEnqueueAll(playlistId: String, next: Bool) async {
        guard let tracks = try? await radioProvider.watchQueue(videoId: "", playlistId: playlistId) else { return }
        let playable = tracks.filter { $0.videoId != nil }
        guard !playable.isEmpty else { return }
        guard let nowPlaying else {
            play(playable, startAt: 0, playlistId: playlistId)
            return
        }
        if queue.isEmpty {
            let seedTrack = Track(index: 1, title: nowPlaying.title, subtitle: nowPlaying.subtitle,
                                  duration: nil, thumbnailURL: nowPlaying.thumbnailURL,
                                  videoId: nowPlaying.videoId, artists: nowPlaying.artists,
                                  albumLink: nowPlaying.albumLink)
            queue = [seedTrack]
            currentIndex = 0
        }
        queue.insert(contentsOf: playable, at: next ? currentIndex + 1 : queue.count)
        persist()
    }

    private func maybeContinueWithRadio() {
        guard autoplayEnabled, repeatMode == .off, currentIndex >= queue.count - 1,
              let seed = nowPlaying?.videoId else { return }
        radioTask?.cancel()
        radioTask = Task { await appendRadio(seed: seed) }
    }

    private var autoplayEnabled: Bool { settings?.autoplay ?? true }

    func appendRadio(seed videoId: String) async {
        let page: RadioPage?
        // A fresh radio re-attributes the queue to the new mix; continuing keeps its attribution.
        let isFreshRadio = radioContinuation == nil
        if let token = radioContinuation {
            page = try? await radioProvider.continueRadio(token)
        } else {
            page = try? await radioProvider.radio(for: videoId)
        }
        guard let page else { return }
        guard autoplayEnabled, nowPlaying?.videoId == videoId, repeatMode == .off,
              currentIndex >= queue.count - 1 else { return }

        let existing = Set(queue.compactMap(\.videoId))
        let continuation = page.tracks.filter { track in
            guard let id = track.videoId else { return false }
            return id != videoId && !existing.contains(id)
        }
        guard !continuation.isEmpty else { return }

        radioContinuation = page.continuation
        albumContext = ""
        if isFreshRadio { playlistContext = MixIds.songRadio(for: videoId) }
        if queue.isEmpty {
            guard let nowPlaying else { return }
            let seedTrack = Track(index: 1, title: nowPlaying.title, subtitle: nowPlaying.subtitle,
                                  duration: nil, thumbnailURL: nowPlaying.thumbnailURL, videoId: videoId,
                                  artists: nowPlaying.artists, albumLink: nowPlaying.albumLink)
            queue = [seedTrack] + continuation
            currentIndex = 0
        } else {
            queue.append(contentsOf: continuation)
        }
        persist()
    }

    // MARK: - Transport

    var isPlaying: Bool { audio.isPlaying }
    var isBuffering: Bool { audio.isBuffering }
    var currentTime: Double { awaitingResume ? restoredPosition : audio.currentTime }
    var duration: Double { awaitingResume ? restoredDuration : audio.duration }
    var bufferedTime: Double { audio.bufferedTime }

    var volume: Double {
        get { level }
        set {
            level = newValue
            isMuted = false
            settings?.volume = newValue
        }
    }

    var isMuted = false {
        didSet {
            audio.volume = isMuted ? 0 : level
            settings?.isMuted = isMuted
        }
    }

    private var level: Double

    var canGoNext: Bool { !queue.isEmpty && (currentIndex + 1 < queue.count || repeatMode == .all) }
    var canGoPrevious: Bool { !queue.isEmpty && (currentIndex > 0 || repeatMode == .all) }

    func togglePlayPause() {
        if awaitingResume {
            resumeRestored()
            return
        }
        audio.togglePlayPause()
        if awaitingAudio, !audio.isPlaying {
            awaitingAudio = false
            isLoading = false
        }
        persist()
        emitPlaybackChange()
    }

    private func handlePlaybackStart() {
        if awaitingAudio {
            awaitingAudio = false
            isLoading = false
        }
        emitPlaybackChange()
    }
    func seek(to seconds: Double) {
        if awaitingResume {
            restoredPosition = restoredDuration > 0 ? min(max(0, seconds), restoredDuration) : max(0, seconds)
            persist()
            return
        }
        audio.seek(to: seconds)
        emitPlaybackChange()
    }

    func skip(by seconds: Double) {
        let target = currentTime + seconds
        seek(to: min(max(0, target), duration > 0 ? duration : target))
    }

    static func speedLabel(_ rate: Double) -> String {
        "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    private func applyPlaybackRate() {
        audio.playbackRate = isEpisode ? playbackRate : 1
    }

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
        // Restart the current track when more than a few seconds in, otherwise step back.
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

    func toggleShuffle() {
        guard !queue.isEmpty, queue.indices.contains(currentIndex) else { return }
        let current = queue[currentIndex]
        if isShuffled {
            var restored = orderBeforeShuffle
            let known = Set(orderBeforeShuffle.map(\.id))
            restored += queue.filter { !known.contains($0.id) }
            queue = restored
            orderBeforeShuffle = []
            isShuffled = false
        } else {
            orderBeforeShuffle = queue
            var rest = queue
            rest.remove(at: currentIndex)
            queue = [current] + rest.shuffled()
            isShuffled = true
        }
        currentIndex = queue.firstIndex { $0.id == current.id } ?? 0
        persist()
    }

    private func resetShuffle() {
        isShuffled = false
        orderBeforeShuffle = []
    }

    // MARK: - Queue editing

    func playQueueItem(at index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        startCurrent()
    }

    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index) else { return }
        let removed = queue.remove(at: index)
        orderBeforeShuffle.removeAll { $0.id == removed.id }

        if index == currentIndex {
            if queue.isEmpty {
                currentIndex = 0
            } else {
                if currentIndex >= queue.count { currentIndex = queue.count - 1 }
                startCurrent()
                return
            }
        } else if index < currentIndex {
            currentIndex -= 1
        }
        persist()
    }

    func moveInQueue(fromOffsets source: IndexSet, toOffset destination: Int) {
        let current = queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
        queue.move(fromOffsets: source, toOffset: destination)
        if let current, let index = queue.firstIndex(where: { $0.id == current.id }) {
            currentIndex = index
        }
        persist()
    }

    func toggleLike() { toggleRating(.liked) }

    func toggleDislike() { toggleRating(.disliked) }

    private func toggleRating(_ rating: LikeStatus) {
        guard let videoId = nowPlaying?.videoId, !isUpdatingLike else { return }
        likeInteracted = true
        let previous = likeStatus
        let target: LikeStatus = likeStatus == rating ? .indifferent : rating
        likeStatus = target
        likeStatusCache[videoId] = target
        isUpdatingLike = true
        Task {
            defer { isUpdatingLike = false }
            do {
                try await likeProvider.setLikeStatus(videoId: videoId, status: target)
            } catch {
                likeStatusCache[videoId] = previous
                if nowPlaying?.videoId == videoId { likeStatus = previous }
            }
        }
        if target == .disliked { next() }
    }

    private func fetchLikeStatus(for videoId: String) {
        likeFetchTask?.cancel()
        likeFetchTask = Task {
            let count = try? await likeProvider.likeCount(for: videoId)
            if !Task.isCancelled, nowPlaying?.videoId == videoId { likeCount = count }
            guard let status = try? await likeProvider.likeStatus(for: videoId) else { return }
            guard !Task.isCancelled else { return }
            likeStatusCache[videoId] = status
            guard nowPlaying?.videoId == videoId, !likeInteracted else { return }
            likeStatus = status
        }
    }

    func knownLikeStatus(for videoId: String, default fallback: LikeStatus = .indifferent) -> LikeStatus {
        if videoId == nowPlaying?.videoId { return likeStatus }
        return likeStatusCache[videoId] ?? fallback
    }

    /// Like rating only when known (no `.indifferent` fallback), so "not liked" differs from "unknown".
    func likeStatusIfKnown(for videoId: String) -> LikeStatus? {
        if videoId == nowPlaying?.videoId { return likeStatus }
        return likeStatusCache[videoId]
    }

    func setLikeStatus(for videoId: String, to status: LikeStatus) {
        let isCurrent = videoId == nowPlaying?.videoId
        let previous = knownLikeStatus(for: videoId)
        if isCurrent {
            likeInteracted = true
            likeStatus = status
        }
        likeStatusCache[videoId] = status
        Task {
            do {
                try await likeProvider.setLikeStatus(videoId: videoId, status: status)
            } catch {
                likeStatusCache[videoId] = previous
                if isCurrent, nowPlaying?.videoId == videoId { likeStatus = previous }
            }
        }
    }

    private func handleTrackFinished() {
        // Crossfade already advanced; ignore the faded-out track's end.
        if crossfadeLoading { return }
        reportFinalWatchtime()
        switch repeatMode {
        case .one:        audio.restart()
        case .off, .all:  next()
        }
    }

    // MARK: - Persistence

    private func restore() {
        guard let snapshot = store?.load() else { return }
        nowPlaying = snapshot.nowPlaying
        queue = snapshot.tracks.map(\.track)
        currentIndex = queue.isEmpty ? 0 : min(max(0, snapshot.currentIndex), queue.count - 1)
        repeatMode = snapshot.repeatMode
        albumContext = snapshot.album
        playlistContext = snapshot.playlistId
        isShuffled = snapshot.isShuffled
        restoredPosition = snapshot.position
        restoredDuration = snapshot.duration
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
            album: albumContext,
            isShuffled: isShuffled,
            playlistId: playlistContext,
            // Mid-load, the engine still reports the previous track's times.
            position: isLoading ? 0 : currentTime,
            duration: isLoading ? 0 : duration
        ))
    }

    private func resumeRestored() {
        let position = restoredPosition > 0 ? restoredPosition : nil
        if !queue.isEmpty {
            startCurrent(at: position)
        } else if let nowPlaying {
            startTrack(title: nowPlaying.title, subtitle: nowPlaying.subtitle,
                       album: nowPlaying.album, thumbnailURL: nowPlaying.thumbnailURL,
                       videoId: nowPlaying.videoId,
                       artists: nowPlaying.artists, albumLink: nowPlaying.albumLink,
                       startAt: position)
        }
    }

    // MARK: - Loading

    private func startCurrent(at position: Double? = nil) {
        guard queue.indices.contains(currentIndex),
              let videoId = queue[currentIndex].videoId else { return }
        let track = queue[currentIndex]
        startTrack(title: track.title, subtitle: track.subtitle, album: albumContext,
                   thumbnailURL: track.thumbnailURL, videoId: videoId,
                   artists: track.artists, albumLink: track.albumLink, startAt: position)
    }

    private func startTrack(title: String, subtitle: String, album: String,
                            thumbnailURL: URL?, videoId: String,
                            artists: [EntityLink] = [], albumLink: EntityLink? = nil,
                            startAt position: Double? = nil) {
        awaitingResume = false
        lastPersistedPosition = 0
        crossfadeArmed = false
        crossfadeLoading = false
        pendingHistory = nil
        playbackPinged = false
        lastWatchtimeAt = -1
        likeStatus = .indifferent
        likeCount = nil
        likeInteracted = false
        nowPlaying = NowPlaying(
            title: title,
            subtitle: subtitle,
            album: album,
            thumbnailURL: thumbnailURL,
            videoId: videoId,
            artists: artists,
            albumLink: albumLink
        )
        loadError = nil
        isLoading = true
        awaitingAudio = false
        if audio.isPlaying { audio.togglePlayPause() }
        if preparedVideoId != videoId {
            preloadTask?.cancel()
            preloadTask = nil
            preparedVideoId = nil
            preparedStream = nil
        }
        persist()
        emitPlaybackChange()
        fetchLikeStatus(for: videoId)

        loadTask?.cancel()
        loadTask = Task { await loadStream(videoId: videoId, startAt: position) }

        maybeContinueWithRadio()
    }

    func loadStream(videoId: String, startAt position: Double? = nil) async {
        do {
            let preferences = settings?.streamPreferences ?? StreamPreferences()
            let resolved: ResolvedStream
            let usedPreloadedStream = preparedVideoId == videoId
            if usedPreloadedStream, let preparedStream {
                resolved = preparedStream
                self.preparedVideoId = nil
                self.preparedStream = nil
            } else {
                resolved = try await resolver.audioStream(videoId: videoId, playlistId: playlistContext,
                                                          preferences: preferences)
            }
            if Task.isCancelled { return }
            let metadata = NowPlayingMetadata(
                title: nowPlaying?.title ?? "",
                artist: Self.cleanedArtist(nowPlaying),
                album: nowPlaying?.album ?? "",
                artworkURL: nowPlaying?.thumbnailURL,
                knownDuration: resolved.duration,
                loudnessDb: resolved.loudnessDb,
                streamEnd: resolved.streamEnd,
                isEpisode: resolved.isEpisode
            )
            isEpisode = resolved.isEpisode
            streamDetails = resolved.details
            applyPlaybackRate()
            if usedPreloadedStream {
                audio.loadPreloaded(url: resolved.url, metadata: metadata)
            } else {
                audio.load(url: resolved.url, metadata: metadata)
            }
            awaitingAudio = true
            if let position { audio.seek(to: position) }
            emitPlaybackChange()
            // History is armed here; handleProgress fires it once the listener is underway.
            armHistory(resolved)
        } catch {
            if !Task.isCancelled {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func armHistory(_ resolved: ResolvedStream) {
        guard resolved.historyURL != nil || resolved.watchtimeURL != nil, resolved.cpn != nil else {
            return
        }
        pendingHistory = resolved
        playbackPinged = false
        lastWatchtimeAt = -1
    }

    private func reportHistoryProgress(current: Double, duration: Double) {
        guard let pending = pendingHistory, let cpn = pending.cpn else { return }
        guard audio.isPlaying, current >= 1 else { return }
        let length = pending.duration ?? (duration > 0 ? duration : nil)

        if !playbackPinged, let playbackURL = pending.historyURL {
            playbackPinged = true
            Task { await historyReporter.reportPlaybackStart(
                playbackURL: playbackURL, cpn: cpn, position: current, length: length) }
        }
        if let watchtimeURL = pending.watchtimeURL, lastWatchtimeAt < 0 || current - lastWatchtimeAt >= 20 {
            lastWatchtimeAt = current
            Task { await historyReporter.reportWatchtime(
                watchtimeURL: watchtimeURL, cpn: cpn, position: current, length: length) }
        }
    }

    private func reportFinalWatchtime() {
        guard playbackPinged, let pending = pendingHistory, let cpn = pending.cpn,
              let watchtimeURL = pending.watchtimeURL else { return }
        let length = pending.duration
        let position = length ?? audio.duration
        Task { await historyReporter.reportWatchtime(
            watchtimeURL: watchtimeURL, cpn: cpn, position: position, length: length) }
    }

    // MARK: - Crossfade

    private func handleProgress(current: Double, duration: Double) {
        reportHistoryProgress(current: current, duration: duration)
        onPlaybackProgress?(current, duration)

        if abs(current - lastPersistedPosition) >= 5 {
            lastPersistedPosition = current
            persist()
        }

        if let seconds = settings?.nextTrackPreloadSeconds,
           seconds > 0, duration > 0, duration - current <= seconds {
            beginPreloadingNext()
        }

        guard let settings, settings.crossfadeEnabled else { return }
        let seconds = settings.crossfadeSeconds
        guard seconds > 0, duration > 0 else { return }

        // Re-arm once the freshly-started track is underway.
        if current < 1.0 { crossfadeArmed = false }

        // Repeat-one loops the same track, so never crossfade out of it.
        guard !crossfadeArmed, repeatMode != .one, canGoNext else { return }
        if duration - current <= seconds {
            crossfadeArmed = true
            beginCrossfade(over: seconds)
        }
    }

    private func beginCrossfade(over seconds: Double) {
        guard !queue.isEmpty else { return }
        let nextIndex: Int
        if currentIndex + 1 < queue.count {
            nextIndex = currentIndex + 1
        } else if repeatMode == .all {
            nextIndex = 0
        } else {
            return
        }
        guard let videoId = queue[nextIndex].videoId else { return }

        let track = queue[nextIndex]
        currentIndex = nextIndex
        crossfadeLoading = true
        pendingHistory = nil
        playbackPinged = false
        lastWatchtimeAt = -1
        likeStatus = .indifferent
        likeCount = nil
        likeInteracted = false
        nowPlaying = NowPlaying(
            title: track.title,
            subtitle: track.subtitle,
            album: albumContext,
            thumbnailURL: track.thumbnailURL,
            videoId: videoId,
            artists: track.artists,
            albumLink: track.albumLink
        )
        loadError = nil
        persist()
        emitPlaybackChange()
        fetchLikeStatus(for: videoId)

        loadTask?.cancel()
        loadTask = Task { await loadCrossfade(videoId: videoId, seconds: seconds) }

        maybeContinueWithRadio()
    }

    private func loadCrossfade(videoId: String, seconds: Double) async {
        do {
            let preferences = settings?.streamPreferences ?? StreamPreferences()
            let resolved: ResolvedStream
            let usedPreloadedStream = preparedVideoId == videoId
            if usedPreloadedStream, let preparedStream {
                resolved = preparedStream
                self.preparedVideoId = nil
                self.preparedStream = nil
            } else {
                resolved = try await resolver.audioStream(videoId: videoId, playlistId: playlistContext,
                                                           preferences: preferences)
            }
            if Task.isCancelled { return }
            let metadata = NowPlayingMetadata(
                title: nowPlaying?.title ?? "",
                artist: Self.cleanedArtist(nowPlaying),
                album: nowPlaying?.album ?? "",
                artworkURL: nowPlaying?.thumbnailURL,
                knownDuration: resolved.duration,
                loudnessDb: resolved.loudnessDb,
                streamEnd: resolved.streamEnd,
                isEpisode: resolved.isEpisode
            )
            isEpisode = resolved.isEpisode
            streamDetails = resolved.details
            applyPlaybackRate()
            if usedPreloadedStream {
                audio.crossfadePreloaded(url: resolved.url, metadata: metadata, duration: seconds)
            } else {
                audio.crossfade(to: resolved.url, metadata: metadata, duration: seconds)
            }
            crossfadeLoading = false
            emitPlaybackChange()
            armHistory(resolved)
        } catch {
            crossfadeLoading = false
            if !Task.isCancelled { startCurrent() }
        }
    }

    private func beginPreloadingNext() {
        guard preparedVideoId == nil, preloadTask == nil,
              repeatMode != .one, let nextTrack = nextQueuedTrack(),
              let videoId = nextTrack.videoId else { return }

        let track = nextTrack
        let playlistId = playlistContext
        let preferences = settings?.streamPreferences ?? StreamPreferences()
        preloadTask = Task { [weak self] in
            guard let self else { return }
            defer { self.preloadTask = nil }
            do {
                let resolved = try await self.resolver.audioStream(videoId: videoId, playlistId: playlistId,
                                                                    preferences: preferences)
                guard !Task.isCancelled,
                      self.nowPlaying?.videoId != videoId,
                      self.nextQueuedTrack()?.videoId == videoId else { return }
                let metadata = NowPlayingMetadata(
                    title: track.title,
                    artist: Self.cleanedArtist(NowPlaying(
                        title: track.title, subtitle: track.subtitle, album: self.albumContext,
                        thumbnailURL: track.thumbnailURL, videoId: videoId,
                        artists: track.artists, albumLink: track.albumLink)),
                    album: self.albumContext,
                    artworkURL: track.thumbnailURL,
                    knownDuration: resolved.duration,
                    loudnessDb: resolved.loudnessDb,
                streamEnd: resolved.streamEnd,
                isEpisode: resolved.isEpisode
                )
                self.preparedVideoId = videoId
                self.preparedStream = resolved
                self.audio.preload(url: resolved.url, metadata: metadata)
            } catch {}
        }
    }

    private func nextQueuedTrack() -> Track? {
        if currentIndex + 1 < queue.count { return queue[currentIndex + 1] }
        guard repeatMode == .all, !queue.isEmpty else { return nil }
        return queue[0]
    }

    // MARK: - Plugin hook

    var currentSnapshot: PlaybackSnapshot? {
        guard let nowPlaying else { return nil }
        return PlaybackSnapshot(
            title: nowPlaying.title,
            artist: Self.cleanedArtist(nowPlaying),
            album: nowPlaying.album,
            videoId: nowPlaying.videoId,
            artists: nowPlaying.artists,
            albumLink: nowPlaying.albumLink,
            thumbnailURL: nowPlaying.thumbnailURL,
            isPlaying: audio.isActuallyPlaying,
            currentTime: currentTime,
            duration: duration
        )
    }

    private func emitPlaybackChange() {
        let snapshot = currentSnapshot
        handoff.update(snapshot)
        onPlaybackChange?(snapshot)
    }

    var nowPlayingArtist: String { Self.cleanedArtist(nowPlaying) }

    private static func cleanedArtist(_ nowPlaying: NowPlaying?) -> String {
        guard let nowPlaying else { return "" }
        let names = nowPlaying.artists.map(\.name).filter { !$0.isEmpty }
        if !names.isEmpty { return names.joined(separator: ", ") }
        return withoutTypeLabel(nowPlaying.subtitle).components(separatedBy: " • ").first ?? ""
    }

    /// Strips the type label, view counts and bare durations from a subtitle.
    static func withoutTypeLabel(_ subtitle: String) -> String {
        var components = subtitle.components(separatedBy: " • ")
        let labels: Set<String> = ["Song", "Video", "Episode", "Podcast"]
        if components.count > 1, let first = components.first, labels.contains(first) {
            components.removeFirst()
        }
        components.removeAll { isViewCount($0) || isDuration($0) }
        return components.joined(separator: " • ")
    }

    /// A view-count component like "3.5M views".
    private static func isViewCount(_ component: String) -> Bool {
        let text = component.trimmingCharacters(in: .whitespaces).lowercased()
        guard text.hasSuffix(" views") || text.hasSuffix(" view") else { return false }
        return text.first?.isNumber ?? false
    }

    /// A bare duration like "2:46" or "1:02:30".
    private static func isDuration(_ component: String) -> Bool {
        let parts = component.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }
}
