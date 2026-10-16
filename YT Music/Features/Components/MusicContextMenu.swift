//
//  MusicContextMenu.swift
//  YT Music
//
//  The right-click context menu shared by cards, rows and queue items.
//

import SwiftUI
import AppKit

private struct LikeMenuButton: View {
    @Environment(PlayerState.self) private var player
    let videoId: String
    /// The rating parsed from this row's response, or nil when it carried none.
    let parsedStatus: LikeStatus?

    var body: some View {
        if let status = player.likeStatusIfKnown(for: videoId) ?? parsedStatus {
            let liked = status == .liked
            Button {
                player.setLikeStatus(for: videoId, to: liked ? .indifferent : .liked)
            } label: {
                Label(liked ? "Remove from Likes" : "Like",
                      systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
        }
    }
}

private struct MusicContextMenu<Extra: View>: ViewModifier {
    @Environment(PlayerState.self) private var player
    @Environment(Navigator.self) private var navigator
    @Environment(AuthStore.self) private var auth
    @Environment(PlaylistCoordinator.self) private var playlists

    let title: String
    let subtitle: String
    let thumbnailURL: URL?
    let videoId: String?
    let playlistId: String?
    let browseId: String?
    let artists: [EntityLink]
    let albumLink: EntityLink?
    /// The browsable page this item opens when it's an entity card (album /
    /// playlist / artist / podcast) rather than a playable track. Drives the
    /// menu's Play / Open entries.
    let entityDestination: EntityDestination?
    /// This track's current like rating, parsed from the row's response so the
    /// "Like" / "Remove from Likes" entry is labelled correctly. `nil` when the
    /// row carried no like info (e.g. a feed-page card), in which case it's
    /// resolved on demand when the menu opens.
    let likeStatus: LikeStatus?
    /// Screen-specific extra actions (e.g. "Remove from history", "Delete
    /// upload") appended below the standard entries. Built by the caller.
    let extraActions: Extra

    private var link: URL? {
        MusicLinks.url(videoId: videoId, playlistId: playlistId, browseId: browseId)
    }

    func body(content: Content) -> some View {
        content.contextMenu {
            if let videoId {
                Button {
                    player.play(
                        title: title,
                        subtitle: subtitle,
                        thumbnailURL: thumbnailURL,
                        videoId: videoId,
                        artists: artists,
                        albumLink: albumLink
                    )
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                Button {
                    player.playNext(
                        title: title,
                        subtitle: subtitle,
                        thumbnailURL: thumbnailURL,
                        videoId: videoId,
                        artists: artists,
                        albumLink: albumLink
                    )
                } label: {
                    Label("Play Next", systemImage: "text.insert")
                }

                Button {
                    player.startRadio(
                        title: title,
                        subtitle: subtitle,
                        thumbnailURL: thumbnailURL,
                        videoId: videoId,
                        artists: artists,
                        albumLink: albumLink
                    )
                } label: {
                    Label("Start radio", systemImage: "antenna.radiowaves.left.and.right")
                }

                if auth.isSignedIn {
                    LikeMenuButton(videoId: videoId, parsedStatus: likeStatus)

                    Button {
                        playlists.requestAdd(videoId: videoId, title: title)
                    } label: {
                        Label("Add to Playlist…", systemImage: "text.badge.plus")
                    }
                }

                Button {
                    navigator.creditsRequest = SongCreditsRequest(
                        videoId: videoId, title: title, subtitle: subtitle, thumbnailURL: thumbnailURL
                    )
                } label: {
                    Label("View Song Credits", systemImage: "person.2")
                }
            } else if let entityDestination {
                entityActions(entityDestination)
            }

            goToArtist
            goToAlbum

            if let link {
                ShareLink(item: link)
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(link.absoluteString, forType: .string)
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            }

            extraActions
        }
    }

    /// Entity cards (album / playlist / artist / podcast) have no video of
    /// their own: queuable collections get the playback/queue actions, artists
    /// get their page's Shuffle / Start radio mixes.
    @ViewBuilder
    private func entityActions(_ destination: EntityDestination) -> some View {
        if let playlistId {
            Button {
                player.playAll(videoId: nil, playlistId: playlistId)
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            Button {
                player.playAll(videoId: nil, playlistId: playlistId, shuffled: true)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            Button {
                player.enqueueAll(playlistId: playlistId, next: true)
            } label: {
                Label("Play Next", systemImage: "text.insert")
            }
            Button {
                player.enqueueAll(playlistId: playlistId, next: false)
            } label: {
                Label("Add to Queue", systemImage: "text.append")
            }
            Button {
                player.playAll(videoId: nil, playlistId: MixIds.playlistRadio(for: playlistId))
            } label: {
                Label("Start radio", systemImage: "antenna.radiowaves.left.and.right")
            }
        } else if destination.kind == .artist {
            Button {
                playArtistMix(destination, radio: false)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            Button {
                playArtistMix(destination, radio: true)
            } label: {
                Label("Start radio", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
    }

    /// Artist cards carry no mix ids, so fetch them from the artist page.
    private func playArtistMix(_ destination: EntityDestination, radio: Bool) {
        Task {
            guard let header = try? await InnerTubeClient.shared.entity(destination).header,
                  let mixId = radio
                    ? header.artistPage?.startRadioPlaylistId ?? header.artistPage?.radioPlaylistId
                    : header.artistPage?.radioPlaylistId
            else { return }
            player.playAll(videoId: nil, playlistId: mixId)
        }
    }

    /// "Go to artist" for a single artist, or a submenu listing each when a track
    /// has several (e.g. "Artist 1", "Artist 2"). An entry is disabled when its
    /// page is already the one on screen.
    @ViewBuilder
    private var goToArtist: some View {
        if artists.count == 1, let artist = artists.first {
            Button {
                navigator.open(artist.destination)
            } label: {
                Label("Go to artist", systemImage: "music.mic")
            }
            .disabled(isCurrentPage(artist))
        } else if artists.count > 1 {
            Menu {
                ForEach(artists, id: \.self) { artist in
                    Button(artist.name) { navigator.open(artist.destination) }
                        .disabled(isCurrentPage(artist))
                }
            } label: {
                Label("Go to artist", systemImage: "music.mic")
            }
        }
    }

    @ViewBuilder
    private var goToAlbum: some View {
        if let albumLink {
            Button {
                navigator.open(albumLink.destination)
            } label: {
                Label("Go to album", systemImage: "square.stack")
            }
            .disabled(isCurrentPage(albumLink))
        }
    }

    /// Whether `link` points at the entity page currently on screen (in whichever
    /// tab's stack), so navigating there would be a no-op.
    private func isCurrentPage(_ link: EntityLink) -> Bool {
        isCurrentPage(link.browseId)
    }

    private func isCurrentPage(_ browseId: String) -> Bool {
        navigator.currentPath.last?.browseId == browseId
    }
}

extension View {
    /// Adds the standard right-click menu for a music item. Playable tracks
    /// (with a `videoId`) get Play / Play Next / Start radio / Like / Add to
    /// Playlist; entity cards (albums, playlists, artists, podcasts — pass
    /// their `entityDestination`) get Play / Shuffle / queue / radio instead. Both kinds get
    /// "Go to artist"/"Go to album" when those links are known, Share / Copy
    /// Link, and any screen-specific `extraActions` appended at the bottom.
    func musicContextMenu<Extra: View>(
        title: String,
        subtitle: String,
        thumbnailURL: URL?,
        videoId: String?,
        playlistId: String?,
        browseId: String?,
        artists: [EntityLink] = [],
        albumLink: EntityLink? = nil,
        entityDestination: EntityDestination? = nil,
        likeStatus: LikeStatus? = nil,
        @ViewBuilder extraActions: () -> Extra = { EmptyView() }
    ) -> some View {
        modifier(MusicContextMenu(
            title: title,
            subtitle: subtitle,
            thumbnailURL: thumbnailURL,
            videoId: videoId,
            playlistId: playlistId,
            browseId: browseId,
            artists: artists,
            albumLink: albumLink,
            entityDestination: entityDestination,
            likeStatus: likeStatus,
            extraActions: extraActions()
        ))
    }
}
