//
//  LibraryViewModel.swift
//  YT Music
//

import SwiftUI

@MainActor
@Observable
final class LibraryViewModel {
    enum State {
        case signedOut
        case loading
        case loaded(LibraryPage)
        case failed(String)
    }

    /// The landing page (every kind, most recent first): the sidebar's list and
    /// the Library tab's "All" chip.
    private(set) var state: State = .loading
    /// The server's filter chips (Playlists, Songs, Albums, …).
    private(set) var chips: [HomeChip] = []
    /// The chip showing in the Library tab; nil for "All" (the landing page).
    private(set) var selectedChip: HomeChip?
    private(set) var chipState: State = .loading

    private var isLoadingMoreLanding = false
    private var isLoadingMoreChip = false

    private let client: InnerTubeClient

    init(client: InnerTubeClient = .shared) {
        self.client = client
    }

    /// What the Library tab shows for the current chip.
    var visibleState: State { selectedChip == nil ? state : chipState }

    func load(isSignedIn: Bool) async {
        guard isSignedIn else {
            state = .signedOut
            chips = []
            selectedChip = nil
            return
        }
        state = .loading
        do {
            let page = try await client.library()
            chips = page.chips
            state = page.isEmpty ? .failed("Your library is empty.") : .loaded(page)
        } catch {
            state = .failed(error.localizedDescription)
        }
        if let selectedChip { await loadChip(selectedChip) }
    }

    func select(_ chip: HomeChip?) async {
        selectedChip = chip
        if let chip { await loadChip(chip) }
    }

    private func loadChip(_ chip: HomeChip) async {
        chipState = .loading
        do {
            let page = try await client.library(browseId: chip.browseId, params: chip.params)
            guard selectedChip == chip else { return }
            chipState = .loaded(page)
        } catch {
            guard selectedChip == chip else { return }
            chipState = .failed(error.localizedDescription)
        }
    }

    /// Appends the landing page's next batch (the sidebar reached its end, or
    /// the "All" grid did).
    func loadMoreLanding() async {
        guard !isLoadingMoreLanding, case .loaded(let page) = state,
              let token = page.continuation else { return }
        isLoadingMoreLanding = true
        defer { isLoadingMoreLanding = false }
        guard let next = try? await client.libraryContinuation(token),
              case .loaded(let current) = state, current.continuation == token else { return }
        state = .loaded(current.appending(next))
    }

    /// Appends the next batch of whatever the Library tab is showing.
    func loadMoreVisible() async {
        guard let chip = selectedChip else { return await loadMoreLanding() }
        guard !isLoadingMoreChip, case .loaded(let page) = chipState,
              let token = page.continuation else { return }
        isLoadingMoreChip = true
        defer { isLoadingMoreChip = false }
        guard let next = try? await client.libraryContinuation(token), selectedChip == chip,
              case .loaded(let current) = chipState, current.continuation == token else { return }
        chipState = .loaded(current.appending(next))
    }

    /// Renames one of the user's own playlists (from a card's context menu),
    /// then reloads the library so the grid reflects it.
    func renamePlaylist(_ playlistId: String, to title: String, isSignedIn: Bool) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await client.renamePlaylist(playlistId: playlistId, title: trimmed)
        await load(isSignedIn: isSignedIn)
    }

    /// Deletes one of the user's own playlists, then reloads the library.
    func deletePlaylist(_ playlistId: String, isSignedIn: Bool) async {
        try? await client.deletePlaylist(playlistId: playlistId)
        await load(isSignedIn: isSignedIn)
    }
}
