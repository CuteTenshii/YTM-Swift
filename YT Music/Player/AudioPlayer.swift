//
//  AudioPlayer.swift
//  YT Music
//
//  @Observable wrapper around AVPlayer. Also publishes to the system Now Playing
//  UI (Control Center / media keys) via MediaPlayer's MPNowPlayingInfoCenter and
//  routes MPRemoteCommandCenter commands back to playback.
//

import AVFoundation
import MediaPlayer
import AppKit
import Observation

@MainActor
@Observable
final class AudioPlayer: AudioOutput {
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    // Events handled by the owner (PlayerState); see AudioOutput.
    @ObservationIgnored var onTrackFinished: (() -> Void)?
    @ObservationIgnored var onNext: (() -> Void)?
    @ObservationIgnored var onPrevious: (() -> Void)?

    // Now Playing
    @ObservationIgnored private let infoCenter = MPNowPlayingInfoCenter.default()
    @ObservationIgnored private let commandCenter = MPRemoteCommandCenter.shared()
    @ObservationIgnored private var metadata = NowPlayingMetadata(title: "", artist: "", album: "", artworkURL: nil)
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    @ObservationIgnored private var loadedArtworkURL: URL?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        addPeriodicObserver()
        setupRemoteCommands()
    }

    // No deinit: a single AudioPlayer lives for the app's lifetime (owned by
    // PlayerState), so the AVPlayer is never deallocated and its observers don't
    // need teardown — which also avoids touching main-actor state from deinit.

    // MARK: - Transport

    func load(url: URL, metadata: NowPlayingMetadata) {
        self.metadata = metadata
        let item = AVPlayerItem(url: url)
        observeEnd(of: item)
        player.replaceCurrentItem(with: item)
        currentTime = 0
        duration = metadata.knownDuration ?? 0
        player.play()
        isPlaying = true

        artwork = nil
        loadArtwork(metadata.artworkURL)
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        guard player.currentItem != nil else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
        updateNowPlayingInfo()
    }

    func restart() {
        guard player.currentItem != nil else { return }
        player.seek(to: .zero)
        currentTime = 0
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
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
                guard let self, self.player.currentItem != nil else { return .noSuchContent }
                if !self.isPlaying { self.togglePlayPause() }
                return .success
            }
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.player.currentItem != nil else { return .noSuchContent }
                if self.isPlaying { self.togglePlayPause() }
                return .success
            }
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.player.currentItem != nil else { return .noSuchContent }
                self.togglePlayPause()
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

    private func addPeriodicObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            // Registered on the main queue, so main-actor access is safe.
            MainActor.assumeIsolated {
                self?.tick(time)
            }
        }
    }

    private func tick(_ time: CMTime) {
        currentTime = time.seconds.isFinite ? time.seconds : 0
        // Prefer the authoritative length; only fall back to AVPlayer's estimate
        // when we don't have one (it can over-report while buffering).
        if let known = metadata.knownDuration, known > 0 {
            duration = known
        } else if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite {
            duration = itemDuration
        }
        updateNowPlayingInfo()
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.updateNowPlayingInfo()
                self.onTrackFinished?()
            }
        }
    }
}
