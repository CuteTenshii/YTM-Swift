//
//  AudioPlayer.swift
//  YT Music
//
//  @Observable wrapper around AVPlayer. Also publishes to the system Now Playing
//  UI (Control Center / media keys) via MediaPlayer's MPNowPlayingInfoCenter and
//  routes MPRemoteCommandCenter commands back to playback.
//
//  Uses two AVPlayers so consecutive tracks can be crossfaded: the incoming
//  track starts on the idle player at volume 0 and the two volumes are ramped
//  over the crossfade duration. With crossfade disabled only one player is ever
//  active and the other stays idle.
//

import AVFoundation
import MediaPlayer
import AppKit
import Observation

@MainActor
@Observable
final class AudioPlayer: AudioOutput {
    private let playerA = AVPlayer()
    private let playerB = AVPlayer()
    /// The player currently driving the now-playing track. Crossfade swaps this.
    @ObservationIgnored private var active: AVPlayer
    @ObservationIgnored private var timeObservers: [(AVPlayer, Any)] = []
    @ObservationIgnored private var timeControlObservers: [NSKeyValueObservation] = []
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var fadeTask: Task<Void, Never>?
    /// Bumped on every new crossfade so a just-superseded fade's cleanup can't
    /// clear the newer `fadeTask` it races against.
    @ObservationIgnored private var fadeGeneration = 0
    /// Guards against firing "track finished" more than once for the same item
    /// (the end notification and the tick backstop can both observe the end).
    @ObservationIgnored private var hasSignalledEnd = false

    /// Live equalizer settings shared with every item's audio tap. Mutating its
    /// `settings` re-equalizes the playing track on the next audio block.
    @ObservationIgnored private let equalizerBox = EqualizerSettingsBox()

    /// Shared spectrum meter, fed by every item's tap and read by the visualizer.
    @ObservationIgnored let spectrum: SpectrumAnalyzer? = SpectrumAnalyzer()

    private(set) var isPlaying = false
    /// The stored intent isn't enough: `load()` marks us playing before the
    /// stream has started flowing. `isActuallyPlaying` is true only once AVPlayer
    /// really advances (timeControlStatus == .playing), so consumers can wait
    /// until audio is genuinely audible.
    var isActuallyPlaying: Bool { isPlaying && active.timeControlStatus == .playing }
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var bufferedTime: Double = 0

    /// Master output gain (0...1). The crossfade ramps are scaled by this, so
    /// changing volume mid-fade still respects the user's level.
    var volume: Double = 1 {
        didSet {
            // While a crossfade owns the per-player volumes, the fade loop picks
            // up the new gain on its next step; otherwise apply it immediately.
            if fadeTask == nil { active.volume = clampedVolume }
        }
    }

    private var clampedVolume: Float { Float(min(max(volume, 0), 1)) }

    // Events handled by the owner (PlayerState); see AudioOutput.
    @ObservationIgnored var onTrackFinished: (() -> Void)?
    @ObservationIgnored var onNext: (() -> Void)?
    @ObservationIgnored var onPrevious: (() -> Void)?
    @ObservationIgnored var onTogglePlayPause: (() -> Void)?
    @ObservationIgnored var onProgress: ((Double, Double) -> Void)?
    /// Fired when the current item transitions to genuinely playing (post-buffer).
    @ObservationIgnored var onPlaybackStart: (() -> Void)?

    // Now Playing
    @ObservationIgnored private let infoCenter = MPNowPlayingInfoCenter.default()
    @ObservationIgnored private let commandCenter = MPRemoteCommandCenter.shared()
    @ObservationIgnored private var metadata = NowPlayingMetadata(title: "", artist: "", album: "", artworkURL: nil)
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    @ObservationIgnored private var loadedArtworkURL: URL?

    init() {
        active = playerA
        for player in [playerA, playerB] {
            // Start playback as soon as there's enough data rather than building a
            // larger anti-stall cushion first — noticeably cuts time-to-first-audio
            // on a decent connection (the stream is fetched progressively, so we
            // don't wait on a full download). May stall more on poor networks.
            player.automaticallyWaitsToMinimizeStalling = false
            addPeriodicObserver(to: player)
            observeTimeControl(of: player)
        }
        setupRemoteCommands()
    }

    // No deinit: a single AudioPlayer lives for the app's lifetime (owned by
    // PlayerState), so the AVPlayers are never deallocated and their observers
    // don't need teardown — which also avoids touching main-actor state from deinit.

    private var idle: AVPlayer { active === playerA ? playerB : playerA }

    /// Builds a player item that starts without scanning the whole file for
    /// precise duration/timing — we already pass an authoritative duration via
    /// `knownDuration`, so AVFoundation doesn't need to read to the end of the
    /// stream before playback can begin (which otherwise stalls the start).
    private func makeItem(url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])
        let item = AVPlayerItem(asset: asset)
        // Keep buffering ~30s ahead once playing. This doesn't gate the start of
        // playback (automaticallyWaitsToMinimizeStalling does), so time-to-first-
        // audio is unchanged — it just builds a cushion so network jitter mid-track
        // doesn't underrun the buffer and stutter.
        item.preferredForwardBufferDuration = 30
        installEqualizer(on: item, asset: asset)
        return item
    }

    /// Attaches an equalizer tap to the item's audio track. The track loads
    /// asynchronously, so the mix is set once it's available (before audio has
    /// meaningfully started); if there's no audio track the item plays as-is.
    private func installEqualizer(on item: AVPlayerItem, asset: AVURLAsset) {
        let box = equalizerBox
        let meter = spectrum
        Task { [weak item] in
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first
            else { return }
            let processor = EqualizerProcessor(box: box, spectrum: meter)
            if let mix = makeEqualizerAudioMix(for: track, processor: processor) {
                item?.audioMix = mix
            }
        }
    }

    // MARK: - Transport

    func load(url: URL, metadata: NowPlayingMetadata) {
        // A hard cut: abandon any in-flight crossfade and silence the idle player.
        fadeTask?.cancel()
        fadeTask = nil
        idle.pause()
        idle.replaceCurrentItem(with: nil)
        idle.volume = clampedVolume

        self.metadata = metadata
        let item = makeItem(url: url)
        observeEnd(of: item)
        hasSignalledEnd = false
        active.volume = clampedVolume
        active.replaceCurrentItem(with: item)
        currentTime = 0
        bufferedTime = 0
        duration = metadata.knownDuration ?? 0
        active.play()
        isPlaying = true

        artwork = nil
        loadArtwork(metadata.artworkURL)
        updateNowPlayingInfo()
    }

    func crossfade(to url: URL, metadata: NowPlayingMetadata, duration: Double) {
        guard duration > 0 else {
            load(url: url, metadata: metadata)
            return
        }
        fadeTask?.cancel()
        fadeGeneration += 1
        let generation = fadeGeneration

        let outgoing = active
        let incoming = idle
        let item = makeItem(url: url)
        incoming.volume = 0
        incoming.replaceCurrentItem(with: item)
        incoming.play()

        // The incoming player becomes the source of truth before observing its
        // end, so end-of-track routes from the track now in front.
        active = incoming
        observeEnd(of: item)
        hasSignalledEnd = false

        self.metadata = metadata
        currentTime = 0
        bufferedTime = 0
        self.duration = metadata.knownDuration ?? 0
        isPlaying = true
        artwork = nil
        loadArtwork(metadata.artworkURL)
        updateNowPlayingInfo()

        fadeTask = Task { [weak self] in
            await self?.runFade(outgoing: outgoing, incoming: incoming, seconds: duration)
            // Only this fade's own completion may clear `fadeTask` — if a newer
            // crossfade has since started, its task owns the slot now.
            if self?.fadeGeneration == generation { self?.fadeTask = nil }
        }
    }

    /// Linearly ramps `outgoing` 1→0 and `incoming` 0→1 over `seconds` (both
    /// scaled by the master volume), then parks the outgoing player so it's ready
    /// to be reused for the next track.
    private func runFade(outgoing: AVPlayer, incoming: AVPlayer, seconds: Double) async {
        let stepInterval = 0.05
        let steps = max(1, Int(seconds / stepInterval))
        for step in 1...steps {
            try? await Task.sleep(nanoseconds: UInt64(stepInterval * 1_000_000_000))
            if Task.isCancelled { return }
            let progress = Float(step) / Float(steps)
            let gain = clampedVolume
            outgoing.volume = gain * (1 - progress)
            incoming.volume = gain * progress
        }
        if Task.isCancelled { return }
        outgoing.pause()
        outgoing.replaceCurrentItem(with: nil)
        outgoing.volume = clampedVolume
        incoming.volume = clampedVolume
    }

    func togglePlayPause() {
        guard active.currentItem != nil else { return }
        if isPlaying {
            active.pause()
            if fadeTask != nil { idle.pause() }
        } else {
            active.play()
            if fadeTask != nil { idle.play() }
        }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        // A small tolerance lets AVPlayer snap to the nearest keyframe instead of
        // decoding to the exact frame, which over a remote stream is the
        // difference between instant scrubbing and a multi-second stall.
        let tolerance = CMTime(seconds: 0.75, preferredTimescale: 600)
        active.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
        currentTime = seconds
        // Seeking away from the end re-arms end detection for this item.
        if duration <= 0 || seconds < duration - 0.5 { hasSignalledEnd = false }
        updateNowPlayingInfo()
    }

    func restart() {
        guard active.currentItem != nil else { return }
        active.seek(to: .zero)
        currentTime = 0
        hasSignalledEnd = false
        active.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func applyEqualizer(_ settings: EqualizerSettings) {
        // The shared box feeds every live tap; the change lands on the next
        // audio block, so the playing track re-equalizes without reloading.
        equalizerBox.settings = settings
    }

    // MARK: - Now Playing

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: metadata.title,
            MPMediaItemPropertyArtist: metadata.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if !metadata.album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = metadata.album
        }
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = isPlaying ? .playing : .paused
    }

    private func loadArtwork(_ url: URL?) {
        guard let url, url != loadedArtworkURL else { return }
        loadedArtworkURL = url
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            let size = image.size
            // Capture Data (Sendable), rebuild the image inside the handler.
            self.artwork = MPMediaItemArtwork(boundsSize: size) { _ in
                NSImage(data: data) ?? NSImage(size: size)
            }
            self.updateNowPlayingInfo()
        }
    }

    private func setupRemoteCommands() {
        commandCenter.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.active.currentItem != nil else { return .noSuchContent }
                if !self.isPlaying { self.onTogglePlayPause?() }
                return .success
            }
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.active.currentItem != nil else { return .noSuchContent }
                if self.isPlaying { self.onTogglePlayPause?() }
                return .success
            }
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.active.currentItem != nil else { return .noSuchContent }
                self.onTogglePlayPause?()
                return .success
            }
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            MainActor.assumeIsolated {
                guard let self,
                      let event = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }
                self.seek(to: event.positionTime)
                return .success
            }
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let onNext = self.onNext else { return .noSuchContent }
                onNext()
                return .success
            }
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let onPrevious = self.onPrevious else { return .noSuchContent }
                onPrevious()
                return .success
            }
        }
    }

    // MARK: - Observation

    /// Fires `onPlaybackStart` when the active player actually starts producing
    /// audio (timeControlStatus → .playing). AVPlayer reports `.playing` only once
    /// it's really advancing, so this excludes the load/buffer phase — but not
    /// brief mid-track stalls, which don't matter for presence.
    private func observeTimeControl(of player: AVPlayer) {
        let observation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard player.timeControlStatus == .playing else { return }
            Task { @MainActor in
                guard let self, self.isPlaying, player === self.active else { return }
                self.onPlaybackStart?()
            }
        }
        timeControlObservers.append(observation)
    }

    private func addPeriodicObserver(to player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        let observer = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            // Registered on the main queue, so main-actor access is safe.
            MainActor.assumeIsolated {
                self?.tick(time, from: player)
            }
        }
        timeObservers.append((player, observer))
    }

    private func tick(_ time: CMTime, from player: AVPlayer) {
        // Ignore ticks from the player that's fading out during a crossfade.
        guard player === active else { return }
        let raw = time.seconds.isFinite ? time.seconds : 0
        // Prefer the authoritative length; only fall back to AVPlayer's estimate
        // when we don't have one (it can over-report while buffering).
        if let known = metadata.knownDuration, known > 0 {
            duration = known
        } else if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite {
            duration = itemDuration
        }
        // Never let the displayed position run past the track length.
        currentTime = duration > 0 ? min(raw, duration) : raw
        bufferedTime = bufferedEnd(of: player.currentItem, around: currentTime, cappedTo: duration)
        updateNowPlayingInfo()
        onProgress?(currentTime, duration)

        // Backstop: if the engine has stopped at (or past) the end but the end
        // notification didn't arrive, treat the track as finished so playback
        // still advances.
        if isPlaying, duration > 0, raw >= duration - 0.5,
           player.timeControlStatus != .playing {
            signalEnd()
        }
    }

    /// The end (in seconds) of the buffered range covering `time`, so the UI can
    /// show how far ahead the stream has cached. Falls back to the furthest
    /// buffered range when none contains the playhead (e.g. just after a seek).
    private func bufferedEnd(of item: AVPlayerItem?, around time: Double, cappedTo duration: Double) -> Double {
        guard let item else { return 0 }
        var furthest = 0.0
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            let start = range.start.seconds
            let end = (range.start + range.duration).seconds
            guard start.isFinite, end.isFinite else { continue }
            if time >= start - 1, time <= end + 0.5 {
                furthest = end
                break
            }
            furthest = max(furthest, end)
        }
        return duration > 0 ? min(furthest, duration) : furthest
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.signalEnd()
            }
        }
    }

    /// Fires `onTrackFinished` exactly once per item.
    private func signalEnd() {
        guard !hasSignalledEnd else { return }
        hasSignalledEnd = true
        isPlaying = false
        updateNowPlayingInfo()
        onTrackFinished?()
    }
}
