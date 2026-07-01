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

    /// The playlist id this page can save, derived from the browse id
    /// (`VL<playlistId>`). Only playlists are savable this way — nil for
    /// albums/artists.
    var savablePlaylistId: String? {
        guard destination.kind == .playlist else { return nil }
        let id = destination.browseId
        return id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
    }

    let destination: EntityDestination
    private let client: InnerTubeClient

    init(destination: EntityDestination, client: InnerTubeClient = .shared) {
        self.destination = destination
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
            state = .loaded(page)
        } catch {
            state = .failed(error.localizedDescription)
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
}
