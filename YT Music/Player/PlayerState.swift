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
        /// Navigable artist links (empty when unknown, e.g. a one-off play).
        var artists: [EntityLink] = []
        /// Navigable album link, if known.
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

        // Custom decode so snapshots persisted before links existed still load
        // (the new keys default to empty rather than failing the whole restore).
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
    /// Whether the queue is currently playing in shuffled order.
    private(set) var isShuffled = false
    /// The queue's order captured when shuffle was turned on, so turning it off
    /// restores the original sequence. Empty when not shuffled.
    private var orderBeforeShuffle: [Track] = []

    /// The current track's like rating. When a track starts it's seeded to
    /// `.indifferent` and then refreshed from the server (`fetchLikeStatus`);
    /// `toggleLike` updates it optimistically.
    private(set) var likeStatus: LikeStatus = .indifferent
    /// True while a like request is in flight (disables the button).
    private(set) var isUpdatingLike = false
    /// Set once the user toggles the like for the current track, so a slower
    /// background status fetch doesn't clobber their action. Reset per track.
    private var likeInteracted = false
    /// Like ratings learned for tracks other than the one playing, so a row's
    /// context menu can offer "Remove from Likes" without a fresh fetch. Keyed
    /// by videoId; the current track's live `likeStatus` takes precedence.
    private var likeStatusCache: [String: LikeStatus] = [:]

    /// The playable tracks (those with a videoId) for the current context, and
    /// the index within it that is currently playing. Empty for one-off plays.
    private(set) var queue: [Track] = []
    private(set) var currentIndex = 0
    private var albumContext = ""

    private let audio: AudioOutput
    private let resolver: StreamResolving
    private let radioProvider: RadioProviding
    private let likeProvider: LikeProviding
    private let historyReporter: WatchHistoryReporting
    private let store: PlaybackStore?
    private let settings: AppSettings?
    private var loadTask: Task<Void, Never>?
    private var radioTask: Task<Void, Never>?
    private var likeFetchTask: Task<Void, Never>?
    /// True after restoring a snapshot until the user actually starts playback:
    /// the track is shown but no stream is loaded yet, so the first play resolves
    /// and starts it rather than toggling an empty engine.
    private var awaitingResume = false
    /// Set once per track when a crossfade into the next track has been kicked
    /// off, so the approaching-end window only triggers it once. Re-armed when a
    /// new track starts playing from the top.
    private var crossfadeArmed = false
    /// True between arming a crossfade and the incoming track actually taking
    /// over, so the outgoing track's natural end doesn't double-advance.
    private var crossfadeLoading = false

    /// The current track's resolved stream, kept so its history beacons can be
    /// fired from real playback progress (not at load). nil until resolved.
    private var pendingHistory: ResolvedStream?
    /// Set once the `playback` beacon has fired for the current track.
    private var playbackPinged = false
    /// Position (seconds) of the last `watchtime` heartbeat; -1 before the first.
    private var lastWatchtimeAt: Double = -1

    /// Notified whenever the now-playing track or play/pause state changes, so
    /// plugins (Discord Rich Presence, etc.) can mirror it. Carries nil when
    /// playback stops.
    var onPlaybackChange: ((PlaybackSnapshot?) -> Void)?

    /// Live audio spectrum for the immersive visualizer (nil under a test fake).
    var spectrum: SpectrumAnalyzer? { audio.spectrum }

    init(audio: AudioOutput? = nil, resolver: StreamResolving? = nil,
         radioProvider: RadioProviding? = nil, store: PlaybackStore? = nil,
         settings: AppSettings? = nil, historyReporter: WatchHistoryReporting? = nil,
         likeProvider: LikeProviding? = nil) {
        self.audio = audio ?? AudioPlayer()
        self.resolver = resolver ?? StreamResolver.shared
        self.radioProvider = radioProvider ?? InnerTubeClient.shared
        self.likeProvider = likeProvider ?? InnerTubeClient.shared
        self.historyReporter = historyReporter ?? InnerTubeClient.shared
        self.store = store
        self.settings = settings

        self.audio.onTrackFinished = { [weak self] in self?.handleTrackFinished() }
        self.audio.onNext = { [weak self] in self?.next() }
        self.audio.onPrevious = { [weak self] in self?.previous() }
        self.audio.onProgress = { [weak self] current, duration in
            self?.handleProgress(current: current, duration: duration)
        }

        // Drive the audio engine's equalizer from settings: apply the persisted
        // configuration now, and re-apply whenever the user changes it.
        if let settings {
            self.audio.applyEqualizer(settings.equalizerSettings)
            settings.onEqualizerChange = { [weak self] eq in self?.audio.applyEqualizer(eq) }
            self.audio.volume = settings.volume
        }

        restore()
    }

    // MARK: - Playback intent

    /// Plays a single track with no surrounding queue (next/previous become no-ops).
    func play(title: String, subtitle: String, album: String = "", thumbnailURL: URL?, videoId: String) {
        queue = []
        currentIndex = 0
        resetShuffle()
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
        resetShuffle()
        startCurrent()
    }

    /// Inserts a track to play right after the current one. With nothing
    /// playing it just plays the track. For a one-off play (empty queue) it
    /// seeds the queue with the current track so the inserted track follows it
    /// (and `previous` still returns to it).
    func playNext(title: String, subtitle: String, thumbnailURL: URL?, videoId: String,
                  artists: [EntityLink] = [], albumLink: EntityLink? = nil) {
        guard let nowPlaying else {
            play(title: title, subtitle: subtitle, thumbnailURL: thumbnailURL, videoId: videoId)
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
        resetShuffle()
        persist()
    }

    /// Autoplay: when the current track has nothing after it (a one-off play, or
    /// the last track of an album/playlist) and repeat is off, fetch a radio
    /// based on it and append it so playback keeps going. No-op when more tracks
    /// already follow or the user explicitly started a radio.
    private func maybeContinueWithRadio() {
        guard repeatMode == .off, currentIndex >= queue.count - 1,
              let seed = nowPlaying?.videoId else { return }
        radioTask?.cancel()
        radioTask = Task { await appendRadio(seed: seed) }
    }

    /// Fetches a radio for `videoId` and appends its (new) tracks to the queue.
    /// Split out so tests can await it directly. Re-checks state after the fetch
    /// in case the user moved on meanwhile.
    func appendRadio(seed videoId: String) async {
        guard let tracks = try? await radioProvider.radio(for: videoId) else { return }
        // Still on the seed, still nothing queued after it, still not repeating.
        guard nowPlaying?.videoId == videoId, repeatMode == .off,
              currentIndex >= queue.count - 1 else { return }

        let existing = Set(queue.compactMap(\.videoId))
        let continuation = tracks.filter { track in
            guard let id = track.videoId else { return false }
            return id != videoId && !existing.contains(id)
        }
        guard !continuation.isEmpty else { return }

        // The appended tracks are radio, not part of any album.
        albumContext = ""
        if queue.isEmpty {
            // One-off play: the seed becomes the head of a fresh queue, radio
            // follows it (so `previous` still returns to the seed).
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
    var currentTime: Double { audio.currentTime }
    var duration: Double { audio.duration }
    var bufferedTime: Double { audio.bufferedTime }

    /// Output volume, 0...1. Forwards to the engine and persists via settings.
    var volume: Double {
        get { audio.volume }
        set {
            audio.volume = newValue
            settings?.volume = newValue
        }
    }

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
        emitPlaybackChange()
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

    /// Toggles shuffle. Turning it on shuffles everything after the current track
    /// (which stays playing as the new queue head); turning it off restores the
    /// pre-shuffle order, keeping the current track current. Tracks queued while
    /// shuffled (radio/play-next) are preserved at the end on restore. No-op with
    /// an empty queue (one-off plays can't shuffle).
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

    /// Clears shuffle state when a brand-new queue replaces the current one, so a
    /// fresh album/playlist plays in its natural order.
    private func resetShuffle() {
        isShuffled = false
        orderBeforeShuffle = []
    }

    // MARK: - Queue editing

    /// Jumps to and plays the track at `index` (tapping a row in the queue
    /// panel). No-op for an out-of-range index.
    func playQueueItem(at index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        startCurrent()
    }

    /// Removes the track at `index`. Removing the current track advances to
    /// whatever slides into its place (or stops if it was the last); removing an
    /// earlier track keeps the current one playing.
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

    /// Reorders the queue (drag-to-reorder in the queue panel), keeping the
    /// currently-playing track current wherever it lands.
    func moveInQueue(fromOffsets source: IndexSet, toOffset destination: Int) {
        let current = queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
        queue.move(fromOffsets: source, toOffset: destination)
        if let current, let index = queue.firstIndex(where: { $0.id == current.id }) {
            currentIndex = index
        }
        persist()
    }

    /// Likes the current track, or removes the like if it's already liked.
    /// Updates the UI optimistically and reverts if the request fails (e.g.
    /// signed out). No-op while a previous like request is still in flight.
    func toggleLike() {
        guard let videoId = nowPlaying?.videoId, !isUpdatingLike else { return }
        likeInteracted = true
        let previous = likeStatus
        let target: LikeStatus = likeStatus == .liked ? .indifferent : .liked
        likeStatus = target
        likeStatusCache[videoId] = target
        isUpdatingLike = true
        Task {
            defer { isUpdatingLike = false }
            do {
                try await likeProvider.setLikeStatus(videoId: videoId, status: target)
            } catch {
                // Revert only if we're still on the same track.
                likeStatusCache[videoId] = previous
                if nowPlaying?.videoId == videoId { likeStatus = previous }
            }
        }
    }

    /// Refreshes `likeStatus` from the server for `videoId`. Applied only if the
    /// user is still on that track and hasn't toggled it meanwhile (their action
    /// wins over a slower fetch). No-op result when signed out.
    private func fetchLikeStatus(for videoId: String) {
        likeFetchTask?.cancel()
        likeFetchTask = Task {
            guard let status = try? await likeProvider.likeStatus(for: videoId) else { return }
            guard !Task.isCancelled else { return }
            likeStatusCache[videoId] = status
            guard nowPlaying?.videoId == videoId, !likeInteracted else { return }
            likeStatus = status
        }
    }

    /// The known like rating for a row's context menu, without a network call:
    /// the live status for the current track (so in-session toggles show), else
    /// an in-session cached toggle, else `fallback` — the rating the row's
    /// response already carried.
    func knownLikeStatus(for videoId: String, default fallback: LikeStatus = .indifferent) -> LikeStatus {
        if videoId == nowPlaying?.videoId { return likeStatus }
        return likeStatusCache[videoId] ?? fallback
    }

    /// Sets a specific track's like rating (from a row's context menu, which may
    /// target a track other than the one playing). Mirrors the change onto the
    /// now-playing UI, and reverts it, when it's the current track.
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
        // A crossfade has already advanced the queue and is loading the next
        // track; the just-ended track is the one we faded out of, so ignore its
        // end rather than advancing a second time.
        if crossfadeLoading { return }
        reportFinalWatchtime()
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
        isShuffled = snapshot.isShuffled
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
            isShuffled: isShuffled
        ))
    }

    /// Starts the restored track (resolving its stream for the first time).
    private func resumeRestored() {
        if !queue.isEmpty {
            startCurrent()
        } else if let nowPlaying {
            startTrack(title: nowPlaying.title, subtitle: nowPlaying.subtitle,
                       album: nowPlaying.album, thumbnailURL: nowPlaying.thumbnailURL,
                       videoId: nowPlaying.videoId,
                       artists: nowPlaying.artists, albumLink: nowPlaying.albumLink)
        }
    }

    // MARK: - Loading

    private func startCurrent() {
        guard queue.indices.contains(currentIndex),
              let videoId = queue[currentIndex].videoId else { return }
        let track = queue[currentIndex]
        startTrack(title: track.title, subtitle: track.subtitle, album: albumContext,
                   thumbnailURL: track.thumbnailURL, videoId: videoId,
                   artists: track.artists, albumLink: track.albumLink)
    }

    private func startTrack(title: String, subtitle: String, album: String,
                            thumbnailURL: URL?, videoId: String,
                            artists: [EntityLink] = [], albumLink: EntityLink? = nil) {
        awaitingResume = false
        crossfadeArmed = false
        crossfadeLoading = false
        pendingHistory = nil
        playbackPinged = false
        lastWatchtimeAt = -1
        likeStatus = .indifferent
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
        persist()
        emitPlaybackChange()
        fetchLikeStatus(for: videoId)

        loadTask?.cancel()
        loadTask = Task { await loadStream(videoId: videoId) }

        maybeContinueWithRadio()
    }

    /// Resolves the stream and hands it to the audio engine. Split out from
    /// `startTrack` so tests can await it directly (no Task race).
    func loadStream(videoId: String) async {
        do {
            let preferences = settings?.streamPreferences ?? StreamPreferences()
            let resolved = try await resolver.audioStream(videoId: videoId, preferences: preferences)
            if Task.isCancelled { return }
            let metadata = NowPlayingMetadata(
                title: nowPlaying?.title ?? "",
                artist: Self.cleanedArtist(nowPlaying),
                album: nowPlaying?.album ?? "",
                artworkURL: nowPlaying?.thumbnailURL,
                knownDuration: resolved.duration
            )
            audio.load(url: resolved.url, metadata: metadata)
            isLoading = false
            emitPlaybackChange()
            // Don't ping history yet — the real client reports a live position once
            // the listener is actually into the track. Arm it; handleProgress fires.
            armHistory(resolved)
        } catch {
            if !Task.isCancelled {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    /// Arms history reporting for a freshly loaded stream. The beacons fire from
    /// real playback progress (see `reportHistoryProgress`), mirroring the web
    /// client, rather than at load time. No-op (logs) if the player response
    /// carried no stats URL.
    private func armHistory(_ resolved: ResolvedStream) {
        guard resolved.historyURL != nil || resolved.watchtimeURL != nil, resolved.cpn != nil else {
            PlaybackLog.note("history: no videostats URL in player response")
            return
        }
        pendingHistory = resolved
        playbackPinged = false
        lastWatchtimeAt = -1
    }

    /// Fires the history beacons as the current track plays: the `playback` beacon
    /// once, then `watchtime` heartbeats with the live position every ~20s — the
    /// shape the real YT Music client uses, and what makes a play land in history.
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

    /// Sends a closing `watchtime` heartbeat at the track's end, so the listen is
    /// recorded as completed. Only when the track actually started reporting.
    private func reportFinalWatchtime() {
        guard playbackPinged, let pending = pendingHistory, let cpn = pending.cpn,
              let watchtimeURL = pending.watchtimeURL else { return }
        let length = pending.duration
        let position = length ?? audio.duration
        Task { await historyReporter.reportWatchtime(
            watchtimeURL: watchtimeURL, cpn: cpn, position: position, length: length) }
    }

    // MARK: - Crossfade

    /// Called each playback tick. Drives history reporting, and — when crossfade
    /// is enabled and the current track is within the crossfade window of its end
    /// — kicks off an overlap into the next track.
    private func handleProgress(current: Double, duration: Double) {
        // History beacons fire from real progress regardless of crossfade settings.
        reportHistoryProgress(current: current, duration: duration)

        guard let settings, settings.crossfadeEnabled else { return }
        let seconds = settings.crossfadeSeconds
        guard seconds > 0, duration > 0 else { return }

        // Re-arm once the freshly-started track is underway again.
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
            let resolved = try await resolver.audioStream(videoId: videoId, preferences: preferences)
            if Task.isCancelled { return }
            let metadata = NowPlayingMetadata(
                title: nowPlaying?.title ?? "",
                artist: Self.cleanedArtist(nowPlaying),
                album: nowPlaying?.album ?? "",
                artworkURL: nowPlaying?.thumbnailURL,
                knownDuration: resolved.duration
            )
            audio.crossfade(to: resolved.url, metadata: metadata, duration: seconds)
            crossfadeLoading = false
            emitPlaybackChange()
            armHistory(resolved)
        } catch {
            // Couldn't resolve the next track in time — fall back to a plain
            // load of the now-current track once the old one ends.
            crossfadeLoading = false
            if !Task.isCancelled { startCurrent() }
        }
    }

    // MARK: - Plugin hook

    /// A point-in-time view of playback for plugins. nil means nothing is playing.
    var currentSnapshot: PlaybackSnapshot? {
        guard let nowPlaying else { return nil }
        return PlaybackSnapshot(
            title: nowPlaying.title,
            artist: Self.cleanedArtist(nowPlaying),
            album: nowPlaying.album,
            videoId: nowPlaying.videoId,
            thumbnailURL: nowPlaying.thumbnailURL,
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration
        )
    }

    private func emitPlaybackChange() {
        onPlaybackChange?(currentSnapshot)
    }

    /// The display artist for the current track (structured links if known, else
    /// parsed from the subtitle). Empty when nothing is playing. Cheap to read
    /// from a view without observing per-tick playback state.
    var nowPlayingArtist: String { Self.cleanedArtist(nowPlaying) }

    /// The artist name for Now Playing / plugins. Prefers the structured artist
    /// links; otherwise parses it out of the subtitle.
    private static func cleanedArtist(_ nowPlaying: NowPlaying?) -> String {
        guard let nowPlaying else { return "" }
        let names = nowPlaying.artists.map(\.name).filter { !$0.isEmpty }
        if !names.isEmpty { return names.joined(separator: ", ") }
        // No links: take just the first component ("Artist") of the subtitle.
        return withoutTypeLabel(nowPlaying.subtitle).components(separatedBy: " • ").first ?? ""
    }

    /// YT Music subtitles often lead with a content-type label
    /// ("Song • Artist • Album • Year"); videos additionally stuff a view count
    /// and length into the byline ("femtanyl • 3.5M views • 2:46"). Drop the
    /// type label, any view-count, and any bare duration component so the line
    /// reads as a clean "Artist • Album" byline everywhere it's shown.
    static func withoutTypeLabel(_ subtitle: String) -> String {
        var components = subtitle.components(separatedBy: " • ")
        let labels: Set<String> = ["Song", "Video", "Episode", "Podcast"]
        if components.count > 1, let first = components.first, labels.contains(first) {
            components.removeFirst()
        }
        components.removeAll { isViewCount($0) || isDuration($0) }
        return components.joined(separator: " • ")
    }

    /// A view-count component like "3.5M views" / "1,234 views" — a leading
    /// number token followed by "view"/"views".
    private static func isViewCount(_ component: String) -> Bool {
        let text = component.trimmingCharacters(in: .whitespaces).lowercased()
        guard text.hasSuffix(" views") || text.hasSuffix(" view") else { return false }
        return text.first?.isNumber ?? false
    }

    /// A bare duration component like "2:46" or "1:02:30" — colon-separated
    /// groups of digits and nothing else.
    private static func isDuration(_ component: String) -> Bool {
        let parts = component.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }
}
