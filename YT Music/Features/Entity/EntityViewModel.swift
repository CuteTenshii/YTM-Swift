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
    /// server's once loaded and updated after a rename, so the toolbar title
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

    /// Whether rows can be dragged to reorder: an editable playlist shown in
    /// its manual order, unfiltered.
    var canReorder: Bool {
        guard isEditablePlaylist, case .loaded(let page) = state else { return false }
        return page.isManuallyOrdered && selectedFilter == nil
    }

    /// Artist subscribe-button state, mutated optimistically by `toggleSubscription`.
    private(set) var subscription: ArtistSubscription?
    /// True while a subscribe/unsubscribe request is in flight (disables the button).
    private(set) var isUpdatingSubscription = false

    /// "Save to library" toggle state for playlist pages: read from the page
    /// header, then flipped only once a save/unsave request succeeds.
    private(set) var isSaved = false
    /// True while a save/unsave request is in flight (disables the button).
    private(set) var isUpdatingSaved = false
    private(set) var isLoadingMore = false
    /// True while a filter or sort reload of the track list is in flight.
    private(set) var isReloadingTracks = false
    private var reloadGeneration = 0
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
            isSaved = page.header.isSaved ?? false
            title = page.header.title
            state = .loaded(page)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// The applied filter chip, per the server.
    var selectedFilter: PlaylistFilter? {
        guard case .loaded(let page) = state else { return nil }
        return page.filters.first(where: \.isSelected)
    }

    /// Filters the track list by `filter`, or clears the filter when nil.
    func applyFilter(_ filter: PlaylistFilter?) async {
        guard filter != selectedFilter, let token = filter?.token ?? selectedFilter?.clearToken else { return }
        await reloadTracks(token)
    }

    func applySort(_ option: PlaylistSortOption) async {
        guard !option.isSelected else { return }
        switch option.action {
        case .reload(let token):
            await reloadTracks(token)
        case .edit(let edit):
            guard let playlistId = editablePlaylistId else { return }
            isReloadingTracks = true
            defer { isReloadingTracks = false }
            guard (try? await client.sortPlaylist(playlistId: playlistId, by: edit)) != nil else { return }
            await refreshPage()
        }
    }

    /// Re-fetches the page after an edit that changes its rows (order, voting).
    private func refreshPage() async {
        guard let page = try? await client.entity(destination) else { return }
        state = .loaded(page)
    }

    /// Moves a row's vote toward `target`, showing it at once and reverting if
    /// the request fails.
    func vote(_ track: Track, _ target: PlaylistItemVote.Status) async {
        guard case .loaded(var page) = state,
              let position = page.tracks.firstIndex(where: { $0.id == track.id }),
              let vote = page.tracks[position].vote,
              let token = vote.token(toward: target) else { return }
        page.tracks[position].vote?.status = target
        state = .loaded(page)
        do {
            try await client.votePlaylistItem(token: token)
        } catch {
            guard case .loaded(var current) = state,
                  let index = current.tracks.firstIndex(where: { $0.id == track.id }) else { return }
            current.tracks[index].vote = vote
            state = .loaded(current)
        }
    }

    /// Replaces the track list (and the filters / sort options, which carry the
    /// new selection) with a reload. The latest request wins.
    private func reloadTracks(_ token: String) async {
        guard case .loaded(let page) = state else { return }
        reloadGeneration += 1
        let generation = reloadGeneration
        isReloadingTracks = true
        let reload = try? await client.entityTrackReload(token, header: page.header)
        guard generation == reloadGeneration else { return }
        isReloadingTracks = false
        guard let reload, case .loaded(var current) = state else { return }
        current.tracks = reload.tracks
        current.continuationToken = reload.continuationToken
        current.filters = reload.filters
        current.sortOptions = reload.sortOptions
        state = .loaded(current)
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
            // A filter may have replaced the list meanwhile.
            guard case .loaded(let current) = state, current.continuationToken == token else { return }
            state = .loaded(current.appending(next))
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

    /// Moves a row within the playlist (drag-to-reorder, with `List.onMove`
    /// offsets). The list updates immediately and reverts if the request fails.
    func moveTrack(fromOffsets source: IndexSet, toOffset destination: Int) async {
        guard let playlistId = editablePlaylistId, canReorder,
              case .loaded(let page) = state,
              let from = source.first, source.count == 1,
              let move = PlaylistMove(tracks: page.tracks, from: from, toOffset: destination,
                                      hasMore: page.continuationToken != nil)
        else { return }
        var updated = page
        updated.tracks = move.tracks
        state = .loaded(updated)
        do {
            try await client.movePlaylistItem(playlistId: playlistId, setVideoId: move.setVideoId,
                                              before: move.successor)
        } catch {
            guard case .loaded(var current) = state,
                  current.tracks.map(\.id) == move.tracks.map(\.id) else { return }
            current.tracks = page.tracks
            state = .loaded(current)
        }
    }

    /// Applies metadata edits (name / description / visibility) to the playlist
    /// this page shows, updating the page and its title only once the request
    /// succeeds (so a failed call leaves the page as it was). Only fields that
    /// actually changed are sent; a nil `privacy` means "leave the visibility
    /// alone" (also the case when the header didn't say). Returns whether the
    /// edits were applied.
    @discardableResult
    func editPlaylist(name: String, description: String, privacy: PlaylistPrivacy?,
                      votePermission: Int?) async -> Bool {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let playlistId = editablePlaylistId, !title.isEmpty,
              case .loaded(var page) = state else { return false }

        let newName = title != page.header.title ? title : nil
        let newDescription = description != page.header.description ? description : nil
        let newPrivacy = privacy != page.header.privacy ? privacy : nil
        let currentVotePermission = page.header.voteOptions.first(where: \.isSelected)?.value
        let newVotePermission = votePermission != currentVotePermission ? votePermission : nil
        guard newName != nil || newDescription != nil || newPrivacy != nil || newVotePermission != nil
        else { return true }

        do {
            try await client.updatePlaylist(
                playlistId: playlistId,
                title: newName,
                description: newDescription,
                privacy: newPrivacy,
                votePermission: newVotePermission
            )
            // Voting adds or removes the rows' vote buttons and can change the order.
            if newVotePermission != nil, let fresh = try? await client.entity(destination) {
                page = fresh
            }
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

/// A playlist row moved to a new position: the reordered, renumbered list,
/// the moved row's `setVideoId`, and the `setVideoId` it now sits before (nil
/// at the very end).
struct PlaylistMove {
    let tracks: [Track]
    let setVideoId: String
    let successor: String?

    /// `from` and `toOffset` follow `Array.move(fromOffsets:toOffset:)`. Nil
    /// for a no-op, a row without a `setVideoId`, or a row landing after the
    /// last loaded track while more remain unloaded (its real successor is
    /// unknown).
    init?(tracks: [Track], from: Int, toOffset destination: Int, hasMore: Bool) {
        guard tracks.indices.contains(from), (0...tracks.count).contains(destination),
              let setVideoId = tracks[from].playlistSetVideoId else { return nil }
        let landed = destination > from ? destination - 1 : destination
        guard landed != from else { return nil }
        var moved = tracks
        moved.move(fromOffsets: [from], toOffset: destination)
        let successor = moved.indices.contains(landed + 1) ? moved[landed + 1].playlistSetVideoId : nil
        if successor == nil && (hasMore || landed + 1 < moved.count) { return nil }
        for position in moved.indices { moved[position].index = position + 1 }
        self.tracks = moved
        self.setVideoId = setVideoId
        self.successor = successor
    }
}
