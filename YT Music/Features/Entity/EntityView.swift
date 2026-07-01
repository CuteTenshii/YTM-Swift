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

    init(destination: EntityDestination) {
        _model = State(initialValue: EntityViewModel(destination: destination))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.state {
            case .loading:
                loadingHeader

            case .loaded(let page):
                content(page)

            case .failed(let message):
                errorView(message)
            }
        }
        .navigationTitle(model.destination.title)
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

        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !page.tracks.isEmpty {
                    HeaderView(header: page.header, tracks: page.tracks, album: album, model: model)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    TrackListView(tracks: page.tracks, album: album)
                        .padding(.horizontal, 24)
                } else {
                    HeaderView(header: page.header, tracks: [], album: album, model: model)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                }

                ForEach(page.shelves) { shelf in
                    ShelfView(shelf: shelf)
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - States

    private var loadingHeader: some View {
        VStack(spacing: 16) {
            ArtworkView(
                url: model.destination.thumbnailURL,
                circular: model.destination.kind == .artist,
                size: 180
            )
            ProgressView()
                .tint(.white)
        }
    }

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

    var body: some View {
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
            Spacer(minLength: 0)
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

    var body: some View {
        HStack(spacing: 14) {
            Text("\(track.index)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            ArtworkView(url: track.thumbnailURL, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .foregroundStyle(.white)
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
            albumLink: track.albumLink
        )
    }
}
