//
//  EntityView.swift
//  YT Music
//
//  Detail page for an album, playlist, or artist: a large header, a track
//  listing (albums/playlists), and any carousels (artist albums/related).
//

import SwiftUI

struct EntityView: View {
    @Environment(AuthStore.self) private var auth
    @State private var model: EntityViewModel
    /// True once the header has scrolled up under the titlebar — flips the
    /// window toolbar from transparent (immersive) to its blurred background.
    @State private var scrolledUnderBar = false

    init(destination: EntityDestination) {
        _model = State(initialValue: EntityViewModel(destination: destination))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.state {
            case .loading:
                EntitySkeleton(circular: model.destination.kind == .artist)

            case .loaded(let page):
                content(page)

            case .failed(let message):
                errorView(message)
            }
        }
        .navigationTitle(model.destination.title)
        // Let the artwork gradient bleed up under the window titlebar while the
        // header is in view; once scrolled past it, restore the blurred bar so
        // the back button + title stay legible over the track list. Dark scheme
        // keeps those controls light in both states.
        .toolbarBackground(scrolledUnderBar ? .visible : .hidden, for: .windowToolbar)
        .toolbarColorScheme(.dark, for: .windowToolbar)
        .task { await model.loadIfNeeded() }
        // Re-check subscription state when auth changes (sign-in/out) or the page
        // is revisited, so the subscribe button reflects the server, not a stale
        // optimistic value.
        .task(id: auth.generation) { await model.revalidateSubscription() }
    }

    // MARK: - Loaded content

    private func content(_ page: EntityPage) -> some View {
        // Tracks played from an album page carry the album name into Now Playing.
        let album = page.header.kind == .album ? page.header.title : ""

        // Read the titlebar inset, then let the scroll content ignore it so the
        // header gradient bleeds under the (transparent) window toolbar. The
        // header pads itself back down by that inset to clear the back button.
        return GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HeaderView(header: page.header, tracks: page.tracks,
                               album: album, model: model, topInset: topInset)

                    if !page.tracks.isEmpty {
                        TrackListView(tracks: page.tracks, album: album)
                            .padding(.horizontal, 24)
                    }

                    ForEach(page.shelves) { shelf in
                        ShelfView(shelf: shelf)
                    }
                }
                .padding(.bottom, 24)
            }
            .ignoresSafeArea(.container, edges: .top)
            // Flip the toolbar background once the tinted header has mostly
            // scrolled out of view, animating the transition.
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y > topInset + 140
            } action: { _, past in
                withAnimation(.easeInOut(duration: 0.25)) { scrolledUnderBar = past }
            }
        }
    }

    // MARK: - States

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await model.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding(40)
        .frame(maxWidth: 380)
    }
}

// MARK: - Loading skeleton

/// Placeholder mirroring the loaded layout — header (artwork + text bars +
/// buttons) above a list of track rows — so the page keeps its shape while the
/// entity loads, instead of a bare spinner.
private struct EntitySkeleton: View {
    /// Artist pages use circular artwork; albums/playlists a rounded square.
    let circular: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                trackList
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
        .shimmering()
        .disabled(true)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 24) {
            SkeletonBox(
                width: 200,
                height: 200,
                cornerRadius: circular ? 100 : 8,
                circular: circular
            )

            VStack(alignment: .leading, spacing: 12) {
                SkeletonBox(width: 320, height: 38, cornerRadius: 8)
                SkeletonBox(width: 220, height: 16)
                SkeletonBox(width: 260, height: 12)
                HStack(spacing: 12) {
                    SkeletonBox(width: 96, height: 34, cornerRadius: 8)
                    SkeletonBox(width: 120, height: 34, cornerRadius: 8)
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }

    private var trackList: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { index in
                row(index: index)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                if index < 7 {
                    Divider().overlay(.white.opacity(0.08))
                }
            }
        }
    }

    private func row(index: Int) -> some View {
        // Vary the title width per row so the list doesn't read as a uniform grid.
        let titleWidths: [CGFloat] = [220, 300, 180, 260, 200, 320, 240, 190]
        return HStack(spacing: 14) {
            SkeletonBox(width: 16, height: 14)
                .frame(width: 28, alignment: .trailing)

            SkeletonBox(width: 40, height: 40, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 6) {
                SkeletonBox(width: titleWidths[index % titleWidths.count], height: 13)
                SkeletonBox(width: 120, height: 11)
            }

            Spacer(minLength: 8)

            SkeletonBox(width: 36, height: 12)
        }
    }
}

// MARK: - Header

private struct HeaderView: View {
    @Environment(PlayerState.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(Downloader.self) private var downloader
    @Environment(AuthStore.self) private var auth
    let header: EntityHeader
    let tracks: [Track]
    let album: String
    let model: EntityViewModel
    /// Height of the window titlebar the header extends under, so its content
    /// can be padded down to clear the back button while the gradient bleeds up.
    let topInset: CGFloat

    /// Prominent colours pulled from the cover art, driving the header gradient.
    @State private var palette: [PaletteColor] = []

    var body: some View {
        Group {
            if header.kind == .artist, let banner = header.bannerURL {
                bannerHeader(banner)
            } else {
                standardHeader
            }
        }
        .task(id: header.thumbnailURL) { await loadPalette() }
    }

    /// The default header: circular/square artwork beside title, subtitle,
    /// description, and the action buttons, over a gradient tinted to the art.
    private var standardHeader: some View {
        HStack(alignment: .bottom, spacing: 24) {
            ArtworkView(
                url: header.thumbnailURL,
                circular: header.prefersCircularArtwork,
                size: 200
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(header.title)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)

                if !header.subtitle.isEmpty {
                    Text(header.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !header.description.isEmpty {
                    Text(header.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                actions
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, topInset + 16)
        .padding(.bottom, 20)
        .background(alignment: .top) { artworkGradient }
    }

    /// A vertical wash built from the two most prominent cover-art colours,
    /// fading to clear at the bottom so it melts into the black page and the
    /// track list below. Fills the header's frame (which the ScrollView extends
    /// under the titlebar), so the tint reaches the window's top edge.
    private var artworkGradient: some View {
        let top = vivid(palette.first, brightness: 0.85)
        let mid = vivid(palette.dropFirst().first ?? palette.first, brightness: 0.7)
        return LinearGradient(
            stops: [
                .init(color: top.opacity(0.85), location: 0),
                .init(color: mid.opacity(0.45), location: 0.55),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .animation(.easeInOut(duration: 0.5), value: palette)
    }

    /// Scales a palette colour so its brightest channel hits `brightness`,
    /// preserving hue. Unlike `adjusted(brightness:)` (which only darkens), this
    /// also lifts dark, muddy tints — the common case for dim cover art — into a
    /// vivid wash that actually reads over the black page.
    private func vivid(_ color: PaletteColor?, brightness target: Double) -> Color {
        guard let color else { return Color.white.opacity(0.12) }
        let mx = max(color.red, color.green, color.blue)
        guard mx > 0 else { return Color(.sRGB, red: target, green: target, blue: target) }
        let k = target / mx
        return Color(.sRGB,
                     red: min(1, color.red * k),
                     green: min(1, color.green * k),
                     blue: min(1, color.blue * k))
    }

    /// Fetches the cover art and extracts its palette off the main actor.
    private func loadPalette() async {
        guard let url = header.thumbnailURL else {
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

    /// Full-bleed artist banner: the wide artwork fills the width, fading to
    /// black at the bottom, with the title and actions overlaid.
    private func bannerHeader(_ url: URL) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.white.opacity(0.06)
                }
            }
            .frame(height: 360)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.35), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(header.title)
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)

                if !header.subtitle.isEmpty {
                    Text(header.subtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                }

                if !header.description.isEmpty {
                    Text(header.description)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(3)
                }

                actions
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The action-button row (play / subscribe / save / download), shared by
    /// both header layouts.
    @ViewBuilder
    private var actions: some View {
        if !tracks.isEmpty || showsSubscribe || showsSave {
            HStack(spacing: 12) {
                if !tracks.isEmpty {
                    Button {
                        player.play(tracks, startAt: 0, album: album)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                if showsSubscribe {
                    subscribeButton
                }

                if showsSave {
                    saveButton
                }

                if downloader.isEnabled && !tracks.isEmpty {
                    downloadButton
                }
            }
            .padding(.top, 6)
        }
    }

    /// Whether to offer the subscribe toggle: artist pages, signed in, with a
    /// subscribe button parsed from the header.
    private var showsSubscribe: Bool {
        header.kind == .artist && auth.isSignedIn && model.subscription != nil
    }

    /// Whether to offer the "Save to library" toggle: playlist pages, signed in.
    private var showsSave: Bool {
        auth.isSignedIn && model.savablePlaylistId != nil
    }

    /// Subscribe / Subscribed toggle for artist pages.
    @ViewBuilder
    private var subscribeButton: some View {
        if let subscription = model.subscription {
            Button {
                Task { await model.toggleSubscription() }
            } label: {
                Label(
                    subscription.isSubscribed ? "Subscribed" : "Subscribe",
                    systemImage: subscription.isSubscribed ? "bell.fill" : "bell"
                )
                .font(.headline)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.bordered)
            .tint(subscription.isSubscribed ? .red : nil)
            .disabled(model.isUpdatingSubscription)
        }
    }

    /// Save / Saved toggle for playlist pages ("Add to library").
    @ViewBuilder
    private var saveButton: some View {
        Button {
            Task { await model.toggleSaved() }
        } label: {
            Label(
                model.isSaved ? "Saved" : "Save to library",
                systemImage: model.isSaved ? "checkmark.circle.fill" : "plus.circle"
            )
            .font(.headline)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.bordered)
        .tint(model.isSaved ? .red : nil)
        .disabled(model.isUpdatingSaved)
    }

    @ViewBuilder
    private var downloadButton: some View {
        Button {
            downloader.download(
                tracks,
                collection: header.title,
                to: settings.effectiveDownloadDirectory,
                preferences: settings.streamPreferences
            )
        } label: {
            Label(downloadLabel, systemImage: "arrow.down.circle")
                .font(.headline)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.bordered)
        .disabled(downloader.isBusy)
    }

    /// "Download album" / "Download playlist", or live batch progress.
    private var downloadLabel: String {
        if case .running(let progress) = downloader.status, progress.total > 1 {
            return "Downloading \(progress.index)/\(progress.total)…"
        }
        return header.kind == .playlist ? "Download playlist" : "Download album"
    }
}

// MARK: - Track list

private struct TrackListView: View {
    let tracks: [Track]
    let album: String

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(track: track, index: index, tracks: tracks, album: album)
                if track.id != tracks.last?.id {
                    Divider().overlay(.white.opacity(0.08))
                }
            }
        }
    }
}

private struct TrackRow: View {
    @Environment(PlayerState.self) private var player
    let track: Track
    let index: Int
    let tracks: [Track]
    let album: String

    @State private var hovering = false

    /// Whether this row is the track currently loaded in the player.
    private var isCurrent: Bool {
        track.videoId != nil && track.videoId == player.nowPlaying?.videoId
    }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(Color.red)
                } else {
                    Text("\(track.index)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, alignment: .trailing)

            ArtworkView(url: track.thumbnailURL, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? Color.red : .white)
                    .lineLimit(1)
                if !track.subtitle.isEmpty {
                    Text(track.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let duration = track.duration {
                Text(duration)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(hovering ? Color.white.opacity(0.06) : .clear)
        .clipShape(.rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { player.play(tracks, startAt: index, album: album) }
        .musicContextMenu(
            title: track.title,
            subtitle: track.subtitle,
            thumbnailURL: track.thumbnailURL,
            videoId: track.videoId,
            playlistId: nil,
            browseId: nil,
            artists: track.artists,
            albumLink: track.albumLink,
            likeStatus: track.likeStatus
        )
    }
}
