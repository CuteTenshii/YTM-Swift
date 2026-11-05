//
//  ImmersiveLyricsView.swift
//  YT Music
//
//  Full-window lyrics overlay with blurred artwork and visualizer modes.
//

import SwiftUI

struct ImmersiveLyricsView: View {
    enum Mode: String, CaseIterable {
        case lyrics, bars, milkdrop

        var icon: String {
            switch self {
            case .lyrics:   "quote.bubble"
            case .bars:     "waveform"
            case .milkdrop: "hurricane"
            }
        }

        var help: LocalizedStringKey {
            switch self {
            case .lyrics:   "nowplaying.immersive.mode.lyrics"
            case .bars:     "nowplaying.immersive.mode.bars"
            case .milkdrop: "nowplaying.immersive.mode.milkdrop"
            }
        }
    }

    let player: PlayerState
    @Binding var isPresented: Bool
    var safeAreaTop: CGFloat = 0

    @Environment(AppSettings.self) private var settings
    @State private var model = LyricsViewModel()
    @State private var mode: Mode = .lyrics
    @State private var palette: [PaletteColor] = []

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                Group {
                    switch mode {
                    case .lyrics:
                        content
                            .mask(edgeFade)
                    case .bars:
                        SpectrumVisualizerView(analyzer: player.spectrum,
                                               colors: palette.map(\.color))
                            .padding(.horizontal, 44)
                            .padding(.vertical, 24)
                    case .milkdrop:
                        MilkdropVisualizerView(analyzer: player.spectrum, colors: palette)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                transport
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: taskKey) { await model.load(query: query, provider: settings.lyricsProvider) }
        .task(id: player.nowPlaying?.thumbnailURL) { await loadPalette() }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color.black
            if palette.isEmpty {
                blurredArtwork
            } else {
                MeshGradient(width: 3, height: 3, points: meshPoints, colors: meshColors)
            }
            Color.black.opacity(0.35)
            LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.65)],
                           startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: palette)
    }

    private var blurredArtwork: some View {
        Group {
            if let url = player.nowPlaying?.thumbnailURL {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.black
                }
                .blur(radius: 70)
                .scaleEffect(1.4)
            }
        }
    }

    private var meshPoints: [SIMD2<Float>] {
        [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.5, 0.5], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ]
    }

    private var meshColors: [Color] {
        let base = palette.map { $0.adjusted(brightness: 0.55).color }
        guard !base.isEmpty else { return Array(repeating: .black, count: 9) }
        return (0..<9).map { base[$0 % base.count] }
    }

    private func loadPalette() async {
        guard let url = player.nowPlaying?.thumbnailURL else {
            palette = []
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            palette = await Task.detached { ArtworkPalette.extract(from: data) }.value
        } catch {
            palette = []
        }
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
            modeToggle
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
            .help("nowplaying.immersive.close")
        }
        .padding(.horizontal, 44)
        .padding(.top, 28 + safeAreaTop)
        .padding(.bottom, 8)
    }

    private var modeToggle: some View {
        Picker("nowplaying.immersive.view", selection: $mode.animation(.easeInOut(duration: 0.2))) {
            ForEach(Mode.allCases, id: \.self) { mode in
                Image(systemName: mode.icon).tag(mode).help(mode.help)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 150)
        .help("nowplaying.immersive.switch")
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
            message(String(localized: "nowplaying.lyrics.empty.title"), detail: player.nowPlaying == nil
                ? String(localized: "nowplaying.lyrics.empty.play")
                : String(format: String(localized: "nowplaying.lyrics.empty.provider"), settings.lyricsProvider.label))

        case .failed(let text):
            message(String(localized: "nowplaying.lyrics.error.title"), detail: text)
        }
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.16),
                .init(color: .black, location: 0.90),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
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
            SeekBar(currentTime: player.currentTime,
                    bufferedTime: player.bufferedTime,
                    duration: player.duration,
                    onSeek: { player.seek(to: $0) })
                .frame(maxWidth: 640)
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
            LoadingPlayButton(size: 44, color: .white)
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

extension PaletteColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    func adjusted(brightness cap: Double) -> PaletteColor {
        let mx = max(red, green, blue)
        guard mx > cap, mx > 0 else { return self }
        let k = cap / mx
        return PaletteColor(red: red * k, green: green * k, blue: blue * k)
    }
}

extension LyricsQuery {
    init?(currentlyPlaying player: PlayerState) {
        guard let track = player.nowPlaying else { return nil }
        self.init(videoId: track.videoId,
                  title: track.title,
                  artist: player.nowPlayingArtist,
                  album: track.album,
                  duration: player.duration > 0 ? player.duration : nil)
    }
}
