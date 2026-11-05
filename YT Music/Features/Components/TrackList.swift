//
//  TrackList.swift
//  YT Music
//

import SwiftUI

struct TrackListView: View {
    let tracks: [Track]
    let album: String
    let hasMore: Bool
    var canRemove = false
    var onRemove: (Track) -> Void = { _ in }
    let onReachedEnd: () -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(tracks.indices, id: \.self) { index in
                let track = tracks[index]
                TrackRow(
                    track: track,
                    index: index,
                    tracks: tracks,
                    album: album,
                    canRemove: canRemove,
                    onRemove: onRemove
                )
                if index < tracks.count - 1 {
                    Divider().overlay(.primary.opacity(0.08))
                }
            }

            if hasMore {
                Color.clear
                    .frame(height: 1)
                    .id(tracks.count)
                    .onAppear(perform: onReachedEnd)
            }
        }
    }
}

struct TrackRow: View {
    @Environment(PlayerState.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(AuthStore.self) private var auth
    let track: Track
    let index: Int
    let tracks: [Track]
    let album: String
    let canRemove: Bool
    let onRemove: (Track) -> Void
    var onVote: ((Track, PlaylistItemVote.Status) -> Void)?

    @State private var hovering = false

    private var isCurrent: Bool {
        track.videoId != nil && track.videoId == player.nowPlaying?.videoId
    }

    private var showsRemoveFromPlaylist: Bool {
        auth.isSignedIn
            && canRemove
            && track.videoId != nil
            && track.playlistSetVideoId != nil
            && track.canRemoveFromPlaylist
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
                    .foregroundStyle(isCurrent ? Color.red : .primary)
                    .lineLimit(1)
                if !track.subtitle.isEmpty {
                    Text(track.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if auth.isSignedIn, let onVote, let vote = track.vote {
                voteButtons(vote, onVote: onVote)
            }

            if let duration = track.duration {
                Text(duration)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .clipShape(.rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(count: settings.playClickCount) { player.play(tracks, startAt: index, album: album) }
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
        ) {
            if showsRemoveFromPlaylist {
                Button(role: .destructive) {
                    onRemove(track)
                } label: {
                    Label("components.track_list.remove_from_playlist", systemImage: "minus.circle")
                }
            }
        }
    }

    private func voteButtons(_ vote: PlaylistItemVote,
                             onVote: @escaping (Track, PlaylistItemVote.Status) -> Void) -> some View {
        HStack(spacing: 6) {
            Button {
                onVote(track, vote.status == .up ? .none : .up)
            } label: {
                Image(systemName: vote.status == .up ? "arrowshape.up.fill" : "arrowshape.up")
            }
            .accessibilityLabel(vote.status == .up ? String(localized: "components.vote.up_remove") : String(localized: "components.vote.up"))

            Text(vote.count)
                .font(.callout.monospacedDigit())
                .frame(minWidth: 20)

            Button {
                onVote(track, vote.status == .down ? .none : .down)
            } label: {
                Image(systemName: vote.status == .down ? "arrowshape.down.fill" : "arrowshape.down")
            }
            .accessibilityLabel(vote.status == .down ? String(localized: "components.vote.down_remove") : String(localized: "components.vote.down"))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }
}
