//
//  ImmersiveLyricsView.swift
//  YT Music
//
//  A full-window, Apple Music–style lyrics experience: the current track's
//  artwork blurred behind big, auto-scrolling synced lyrics, with a compact
//  transport strip. Presented as an animated overlay from the now-playing bar
//  (macOS has no full-screen cover), dismissed with the close button or Escape.
//

import SwiftUI

struct ImmersiveLyricsView: View {
    let player: PlayerState
    @Binding var isPresented: Bool

    @Environment(AppSettings.self) private var settings
    @State private var model = LyricsViewModel()

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                transport
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: taskKey) { await model.load(query: query, provider: settings.lyricsProvider) }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color.black
            if let url = player.nowPlaying?.thumbnailURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.black
                }
                .blur(radius: 70)
                .scaleEffect(1.4)   // hide the blur's soft edges
                .overlay(Color.black.opacity(0.5))
                .overlay(
                    LinearGradient(colors: [.black.opacity(0.6), .clear, .black.opacity(0.7)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
        }
        .clipped()
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ArtworkView(url: player.nowPlaying?.thumbnailURL, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.nowPlaying?.title ?? "")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(player.nowPlayingArtist)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { isPresented = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(11)
                    .background(.white.opacity(0.15), in: .circle)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close lyrics")
        }
        .padding(.horizontal, 44)
        .padding(.top, 28)
        .padding(.bottom, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.large)
                .tint(.white)

        case .loaded(let lyrics):
            if lyrics.isSynced {
                SyncedLyricsScroller(player: player, lines: lyrics.lines,
                                     source: lyrics.source, style: .immersive)
            } else {
                PlainLyricsView(lyrics: lyrics, foreground: .white,
                                font: .title3.weight(.medium), alignment: .center)
                    .padding(.horizontal, 44)
            }

        case .unavailable:
            message("No lyrics", detail: player.nowPlaying == nil
                ? "Play a track to see its lyrics."
                : "No lyrics from \(settings.lyricsProvider.label) for this track.")

        case .failed(let text):
            message("Couldn't load lyrics", detail: text)
        }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(.white)
            Text(detail).font(.callout).foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Transport

    private var transport: some View {
        VStack(spacing: 12) {
            if player.duration > 0 {
                SeekBar(currentTime: player.currentTime,
                        bufferedTime: player.bufferedTime,
                        duration: player.duration,
                        onSeek: { player.seek(to: $0) })
                    .frame(maxWidth: 640)
            }
            HStack(spacing: 34) {
                Button(action: player.previous) {
                    Image(systemName: "backward.fill").font(.system(size: 20))
                        .foregroundStyle(player.canGoPrevious ? .white : .white.opacity(0.35))
                }
                .buttonStyle(.plain).disabled(!player.canGoPrevious)

                playButton

                Button(action: player.next) {
                    Image(systemName: "forward.fill").font(.system(size: 20))
                        .foregroundStyle(player.canGoNext ? .white : .white.opacity(0.35))
                }
                .buttonStyle(.plain).disabled(!player.canGoNext)
            }
        }
        .padding(.horizontal, 44)
        .padding(.bottom, 32)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var playButton: some View {
        if player.isLoading {
            ProgressView().controlSize(.small).tint(.white).frame(width: 44, height: 44)
        } else {
            Button(action: player.togglePlayPause) {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(player.loadError != nil)
        }
    }

    // MARK: - Query

    private var query: LyricsQuery? { LyricsQuery(currentlyPlaying: player) }

    private var taskKey: String {
        "\(player.nowPlaying?.videoId ?? "")|\(settings.lyricsProvider.rawValue)"
    }
}

extension LyricsQuery {
    /// Builds a lyrics query for the player's current track, or nil when nothing
    /// is playing.
    init?(currentlyPlaying player: PlayerState) {
        guard let track = player.nowPlaying else { return nil }
        self.init(videoId: track.videoId,
                  title: track.title,
                  artist: player.nowPlayingArtist,
                  album: track.album,
                  duration: player.duration > 0 ? player.duration : nil)
    }
}
