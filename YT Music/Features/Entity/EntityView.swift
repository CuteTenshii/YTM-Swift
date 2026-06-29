//
//  EntityView.swift
//  YT Music
//
//  Detail page for an album, playlist, or artist: a large header, a track
//  listing (albums/playlists), and any carousels (artist albums/related).
//

import SwiftUI

struct EntityView: View {
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
    }

    // MARK: - Loaded content

    private func content(_ page: EntityPage) -> some View {
        // Tracks played from an album page carry the album name into Now Playing.
        let album = page.header.kind == .album ? page.header.title : ""

        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !page.tracks.isEmpty {
                    HeaderView(header: page.header, tracks: page.tracks, album: album)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    TrackListView(tracks: page.tracks, album: album)
                        .padding(.horizontal, 24)
                } else {
                    HeaderView(header: page.header, tracks: [], album: album)
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
    let header: EntityHeader
    let tracks: [Track]
    let album: String

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
                    .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
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
            browseId: nil
        )
    }
}
