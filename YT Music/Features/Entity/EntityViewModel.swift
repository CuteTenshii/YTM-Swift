//
//  EntityViewModel.swift
//  YT Music
//

import SwiftUI

@MainActor
@Observable
final class EntityViewModel {
    enum State {
        case loading
        case loaded(EntityPage)
        case failed(String)
    }

    private(set) var state: State = .loading

    /// The page's title: the destination's at push time, replaced by the
    /// server's once loaded and updated after a rename, so the window title
    /// stays in sync with the page.
    private(set) var title: String

    /// Whether this page shows one of the signed-in user's own (editable)
    /// playlists: rows of playlists the server lets the user edit carry a
    /// remove-from-playlist action in their menus — the permission signal
    /// (`playlistSetVideoId` alone isn't: any playlist's rows may carry one).
    var isEditablePlaylist: Bool {
        guard editablePlaylistId != nil, case .loaded(let page) = state else { return false }
        return page.tracks.contains { $0.canRemoveFromPlaylist }
    }

    /// Artist subscribe-button state, mutated optimistically by `toggleSubscription`.
    private(set) var subscription: ArtistSubscription?
    /// True while a subscribe/unsubscribe request is in flight (disables the button).
    private(set) var isUpdatingSubscription = false

    /// "Save to library" toggle state for playlist pages. Optimistic, like the
    /// subscribe button: flipped only once the request succeeds. We can't read
    /// the initial saved state back from the browse response, so it starts off;
    /// re-saving an already-saved playlist is an idempotent server no-op.
    private(set) var isSaved = false
    /// True while a save/unsave request is in flight (disables the button).
    private(set) var isUpdatingSaved = false
    private(set) var isLoadingMore = false
    private var playlistSearchIndex: [Track]?

    /// The playlist id this page can save, derived from the browse id
    /// (`VL<playlistId>`). Only playlists are savable this way — nil for
    /// albums/artists.
    var savablePlaylistId: String? {
        guard destination.kind == .playlist else { return nil }
        let id = destination.browseId
        return id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
    }

    /// The id of one of the user's own, *editable* playlists when this page is
    /// one — `savablePlaylistId` excluding the system playlists ("Liked
    /// Music", saved episodes), which carry playlist-shaped data (even row
    /// `setVideoId`s) but reject edits. Gates every edit affordance.
    var editablePlaylistId: String? {
        guard let id = savablePlaylistId, !id.isSystemPlaylistId else { return nil }
        return id
    }

    let destination: EntityDestination
    private let client: InnerTubeClient

    init(destination: EntityDestination, client: InnerTubeClient = .shared) {
        self.destination = destination
        self.title = destination.title
        self.client = client
    }

    func loadIfNeeded() async {
        if case .loaded = state { return }
        await load()
    }

    func load() async {
        state = .loading
        do {
            let page = try await client.entity(destination)
            subscription = page.header.subscription
            title = page.header.title
            state = .loaded(page)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMore() async {
        guard !isLoadingMore, case .loaded(let page) = state,
              let token = page.continuationToken else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let next = try await client.entityContinuation(
                token,
                startIndex: page.tracks.count + 1,
                header: page.header
            )
            state = .loaded(page.appending(next))
        } catch {
            // Keep the current page and allow a later scroll attempt to retry.
        }
    }

    func searchPlaylist(_ query: String) async -> [Track]? {
        guard destination.kind == .playlist,
              let playlistId = savablePlaylistId else { return nil }

        do {
            if playlistSearchIndex == nil {
                playlistSearchIndex = try await client.playlistFilterMetadata(playlistId: playlistId)
            }
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = playlistSearchIndex?.filter { track in
                ([track.title, track.subtitle, track.albumLink?.name ?? ""] + track.searchTerms)
                    .contains { $0.localizedCaseInsensitiveContains(needle) }
            } ?? []
            let hydrated = try? await client.playlistFilterSearch(
                playlistId: playlistId, tracks: matches
            )
            let hydratedByVideoId = Dictionary(
                (hydrated ?? []).compactMap { track in
                    track.videoId.map { ($0, track) }
                }, uniquingKeysWith: { first, _ in first }
            )
            return matches.enumerated().map { offset, track in
                let enriched = track.videoId.flatMap { hydratedByVideoId[$0] } ?? track
                var track = enriched
                track.index = offset + 1
                return track
            }
        } catch {
            return nil
        }
    }


    /// Toggles the artist subscription, updating local state only once the request
    /// succeeds (so a failed call leaves the button as it was), then reconciles
    /// against the server's actual state so optimism can't drift.
    func toggleSubscription() async {
        guard let current = subscription, !isUpdatingSubscription else { return }
        let target = !current.isSubscribed
        isUpdatingSubscription = true
        defer { isUpdatingSubscription = false }
        do {
            try await client.setSubscription(
                channelId: current.channelId,
                params: target ? current.subscribeParams : current.unsubscribeParams,
                subscribe: target
            )
            subscription?.isSubscribed = target
            await revalidateSubscription()
        } catch {
            // Leave the previous state intact on failure.
        }
    }

    /// Re-reads the artist's subscribe-button state from the server and updates
    /// the local copy, so the button reflects reality after a toggle or an
    /// external change (e.g. subscribing on another device, or signing in while
    /// the page is open). No-op for non-artist pages or before the page loads.
    func revalidateSubscription() async {
        guard destination.kind == .artist, case .loaded = state else { return }
        guard let page = try? await client.entity(destination) else { return }
        if let fresh = page.header.subscription, !isUpdatingSubscription {
            subscription = fresh
        }
    }

    /// Adds the playlist to (or removes it from) the signed-in user's library,
    /// updating local state only once the request succeeds (so a failed call
    /// leaves the button as it was).
    func toggleSaved() async {
        guard let playlistId = savablePlaylistId, !isUpdatingSaved else { return }
        let target = !isSaved
        isUpdatingSaved = true
        defer { isUpdatingSaved = false }
        do {
            try await client.setPlaylistSaved(playlistId: playlistId, saved: target)
            isSaved = target
        } catch {
            // Leave the previous state intact on failure.
        }
    }

    /// Removes a track from the playlist this page shows. Only called for rows
    /// that carry a `playlistSetVideoId` (present exactly when the signed-in
    /// user can edit the playlist); like the other toggles, the page is updated
    /// only once the request succeeds, so a failed call leaves the list as it
    /// was. Returns whether the row was removed.
    @discardableResult
    func removeFromPlaylist(_ track: Track) async -> Bool {
        guard let playlistId = editablePlaylistId,
              let videoId = track.videoId,
              let setVideoId = track.playlistSetVideoId,
              track.canRemoveFromPlaylist,
              case .loaded(let page) = state else { return false }
        do {
            try await client.removeFromPlaylist(
                playlistId: playlistId,
                items: [(videoId: videoId, setVideoId: setVideoId)]
            )
            var updated = page
            updated.tracks.removeAll { $0.id == track.id }
            for position in updated.tracks.indices {
                updated.tracks[position].index = position + 1
            }
            state = .loaded(updated)
            return true
        } catch {
            return false
        }
    }

    /// Applies metadata edits (name / description / visibility) to the playlist
    /// this page shows, updating the page and its title only once the request
    /// succeeds (so a failed call leaves the page as it was). Only fields that
    /// actually changed are sent; a nil `privacy` means "leave the visibility
    /// alone" (also the case when the header didn't say). Returns whether the
    /// edits were applied.
    @discardableResult
    func editPlaylist(name: String, description: String, privacy: PlaylistPrivacy?) async -> Bool {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let playlistId = editablePlaylistId, !title.isEmpty,
              case .loaded(var page) = state else { return false }

        let newName = title != page.header.title ? title : nil
        let newDescription = description != page.header.description ? description : nil
        let newPrivacy = privacy != page.header.privacy ? privacy : nil
        guard newName != nil || newDescription != nil || newPrivacy != nil else { return true }

        do {
            try await client.updatePlaylist(
                playlistId: playlistId,
                title: newName,
                description: newDescription,
                privacy: newPrivacy
            )
            page.header.title = title
            page.header.description = description
            if let newPrivacy { page.header.privacy = newPrivacy }
            state = .loaded(page)
            self.title = title
            return true
        } catch {
            return false
        }
    }

    /// Deletes the playlist this page shows (owned playlists only — the server
    /// rejects deleting a playlist you don't own). Returns whether it was
    /// deleted; the caller pops the page when it was.
    @discardableResult
    func deletePlaylist() async -> Bool {
        guard let playlistId = editablePlaylistId else { return false }
        do {
            try await client.deletePlaylist(playlistId: playlistId)
            return true
        } catch {
            return false
        }
    }
}
