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
    let parsedStatus: LikeStatus?

    var body: some View {
        if let status = player.likeStatusIfKnown(for: videoId) ?? parsedStatus {
            let liked = status == .liked
            Button {
                player.setLikeStatus(for: videoId, to: liked ? .indifferent : .liked)
            } label: {
                Label(liked ? String(localized: "components.menu.unlike") : String(localized: "components.menu.like"),
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
    let entityDestination: EntityDestination?
    let likeStatus: LikeStatus?
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
                    Label("common.play", systemImage: "play.fill")
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
                    Label("components.menu.play_next", systemImage: "text.insert")
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
                    Label("components.menu.start_radio", systemImage: "antenna.radiowaves.left.and.right")
                }

                if auth.isSignedIn {
                    LikeMenuButton(videoId: videoId, parsedStatus: likeStatus)

                    Button {
                        playlists.requestAdd(videoId: videoId, title: title)
                    } label: {
                        Label("components.menu.add_to_playlist", systemImage: "text.badge.plus")
                    }
                }

                Button {
                    navigator.creditsRequest = SongCreditsRequest(
                        videoId: videoId, title: title, subtitle: subtitle, thumbnailURL: thumbnailURL
                    )
                } label: {
                    Label("components.menu.credits", systemImage: "person.2")
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
                    Label("components.menu.copy_link", systemImage: "link")
                }
            }

            extraActions
        }
    }

    @ViewBuilder
    private func entityActions(_ destination: EntityDestination) -> some View {
        if let playlistId {
            Button {
                player.playAll(videoId: nil, playlistId: playlistId)
            } label: {
                Label("common.play", systemImage: "play.fill")
            }
            Button {
                player.playAll(videoId: nil, playlistId: playlistId, shuffled: true)
            } label: {
                Label("common.shuffle", systemImage: "shuffle")
            }
            Button {
                player.enqueueAll(playlistId: playlistId, next: true)
            } label: {
                Label("components.menu.play_next", systemImage: "text.insert")
            }
            Button {
                player.enqueueAll(playlistId: playlistId, next: false)
            } label: {
                Label("components.menu.add_to_queue", systemImage: "text.append")
            }
            Button {
                player.playAll(videoId: nil, playlistId: MixIds.playlistRadio(for: playlistId))
            } label: {
                Label("components.menu.start_radio", systemImage: "antenna.radiowaves.left.and.right")
            }
        } else if destination.kind == .artist {
            Button {
                playArtistMix(destination, radio: false)
            } label: {
                Label("common.shuffle", systemImage: "shuffle")
            }
            Button {
                playArtistMix(destination, radio: true)
            } label: {
                Label("components.menu.start_radio", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
    }

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

    @ViewBuilder
    private var goToArtist: some View {
        if artists.count == 1, let artist = artists.first {
            Button {
                navigator.open(artist.destination)
            } label: {
                Label("components.menu.go_artist", systemImage: "music.mic")
            }
            .disabled(isCurrentPage(artist))
        } else if artists.count > 1 {
            Menu {
                ForEach(artists, id: \.self) { artist in
                    Button(artist.name) { navigator.open(artist.destination) }
                        .disabled(isCurrentPage(artist))
                }
            } label: {
                Label("components.menu.go_artist", systemImage: "music.mic")
            }
        }
    }

    @ViewBuilder
    private var goToAlbum: some View {
        if let albumLink {
            Button {
                navigator.open(albumLink.destination)
            } label: {
                Label("components.menu.go_album", systemImage: "square.stack")
            }
            .disabled(isCurrentPage(albumLink))
        }
    }

    private func isCurrentPage(_ link: EntityLink) -> Bool {
        isCurrentPage(link.browseId)
    }

    private func isCurrentPage(_ browseId: String) -> Bool {
        navigator.currentPath.last?.browseId == browseId
    }
}

extension View {
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
