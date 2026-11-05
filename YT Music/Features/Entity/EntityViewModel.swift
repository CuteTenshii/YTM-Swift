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

    private(set) var title: String

    /// Editable playlist: `playlistSetVideoId` alone isn't a permission signal, remove actions are.
    var isEditablePlaylist: Bool {
        guard editablePlaylistId != nil, case .loaded(let page) = state else { return false }
        return page.tracks.contains { $0.canRemoveFromPlaylist }
    }

    var canReorder: Bool {
        guard isEditablePlaylist, case .loaded(let page) = state else { return false }
        return page.isManuallyOrdered && selectedFilter == nil
    }

    private(set) var subscription: ArtistSubscription?
    private(set) var isUpdatingSubscription = false

    private(set) var isSaved = false
    private(set) var isUpdatingSaved = false
    private(set) var isLoadingMore = false
    private(set) var isReloadingTracks = false
    private var reloadGeneration = 0
    private var playlistSearchIndex: [Track]?

    var savablePlaylistId: String? {
        let id = destination.browseId
        switch destination.kind {
        case .playlist: return id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
        case .podcast: return id.hasPrefix("MPSP") ? String(id.dropFirst(4)) : nil
        default: return nil
        }
    }

    /// System playlists (Liked Music, saved episodes) carry playlist-shaped data but reject edits.
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
            subscription = page.header.artistPage?.subscription
            isSaved = page.header.isSaved ?? false
            title = page.header.title
            state = .loaded(page)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    var selectedFilter: PlaylistFilter? {
        guard case .loaded(let page) = state else { return nil }
        return page.filters.first(where: \.isSelected)
    }

    func applyFilter(_ filter: PlaylistFilter?) async {
        guard filter != selectedFilter, let token = filter?.token ?? selectedFilter?.clearToken else { return }
        await reloadTracks(token)
    }

    func applySort(_ option: PlaylistSortOption) async {
        guard !option.isSelected else { return }
        switch option.action {
        case .reload(let token):
            await reloadTracks(token)
        case .browse(let browseId, let params):
            await reloadTracks {
                try await self.client.entityReload(browseId: browseId, params: params, fallback: self.destination)
            }
        case .edit(let edit):
            guard let playlistId = editablePlaylistId else { return }
            isReloadingTracks = true
            defer { isReloadingTracks = false }
            guard (try? await client.sortPlaylist(playlistId: playlistId, by: edit)) != nil else { return }
            await refreshPage()
        }
    }

    private func refreshPage() async {
        guard let page = try? await client.entity(destination) else { return }
        state = .loaded(page)
    }

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

    private func reloadTracks(_ token: String) async {
        guard case .loaded(let page) = state else { return }
        await reloadTracks { try await self.client.entityTrackReload(token, header: page.header) }
    }

    private func reloadTracks(_ load: () async throws -> EntityPage) async {
        reloadGeneration += 1
        let generation = reloadGeneration
        isReloadingTracks = true
        let reload = try? await load()
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
            guard case .loaded(let current) = state, current.continuationToken == token else { return }
            state = .loaded(current.appending(next))
        } catch {
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
        }
    }

    func revalidateSubscription() async {
        guard destination.kind == .artist, case .loaded = state else { return }
        guard let page = try? await client.entity(destination) else { return }
        if let fresh = page.header.artistPage?.subscription, !isUpdatingSubscription {
            subscription = fresh
        }
    }

    func toggleSaved() async {
        guard let playlistId = savablePlaylistId, !isUpdatingSaved else { return }
        let target = !isSaved
        isUpdatingSaved = true
        defer { isUpdatingSaved = false }
        do {
            try await client.setPlaylistSaved(playlistId: playlistId, saved: target)
            isSaved = target
        } catch {
        }
    }

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

    @discardableResult
    func editPlaylist(name: String, description: String, privacy: PlaylistPrivacy?,
                      votePermission: Int?) async -> Bool {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let playlistId = editablePlaylistId, !title.isEmpty,
              case .loaded(var page) = state else { return false }

        let newName = title != page.header.title ? title : nil
        let newDescription = description != page.header.description ? description : nil
        let newPrivacy = privacy != page.header.collection?.privacy ? privacy : nil
        let currentVotePermission = page.header.collection?.voteOptions.first(where: \.isSelected)?.value
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
            if newVotePermission != nil, let fresh = try? await client.entity(destination) {
                page = fresh
            }
            page.header.title = title
            page.header.description = description
            if let newPrivacy { page.header.collection?.privacy = newPrivacy }
            state = .loaded(page)
            self.title = title
            return true
        } catch {
            return false
        }
    }

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

struct PlaylistMove {
    let tracks: [Track]
    let setVideoId: String
    let successor: String?

    init?(tracks: [Track], from: Int, toOffset destination: Int, hasMore: Bool) {
        guard tracks.indices.contains(from), (0...tracks.count).contains(destination),
              let setVideoId = tracks[from].playlistSetVideoId else { return nil }
        let landed = destination > from ? destination - 1 : destination
        guard landed != from else { return nil }
        var moved = tracks
        moved.move(fromOffsets: [from], toOffset: destination)
        let successor = moved.indices.contains(landed + 1) ? moved[landed + 1].playlistSetVideoId : nil
        // A row landing before unloaded rows has an unknown successor.
        if successor == nil && (hasMore || landed + 1 < moved.count) { return nil }
        for position in moved.indices { moved[position].index = position + 1 }
        self.tracks = moved
        self.setVideoId = setVideoId
        self.successor = successor
    }
}
