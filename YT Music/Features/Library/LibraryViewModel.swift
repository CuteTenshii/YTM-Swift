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

    private(set) var state: State = .loading
    private(set) var chips: [FeedChip] = []
    private(set) var selectedChip: FeedChip?
    private(set) var chipState: State = .loading

    private var isLoadingMoreLanding = false
    private var isLoadingMoreChip = false

    private let client: InnerTubeClient

    init(client: InnerTubeClient = .shared) {
        self.client = client
    }

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

    func select(_ chip: FeedChip?) async {
        selectedChip = chip
        if let chip { await loadChip(chip) }
    }

    private func loadChip(_ chip: FeedChip) async {
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

    func loadMoreLanding() async {
        guard !isLoadingMoreLanding, case .loaded(let page) = state,
              let token = page.continuation else { return }
        isLoadingMoreLanding = true
        defer { isLoadingMoreLanding = false }
        guard let next = try? await client.libraryContinuation(token),
              case .loaded(let current) = state, current.continuation == token else { return }
        state = .loaded(current.appending(next))
    }

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

    func renamePlaylist(_ playlistId: String, to title: String, isSignedIn: Bool) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await client.renamePlaylist(playlistId: playlistId, title: trimmed)
        await load(isSignedIn: isSignedIn)
    }

    func deletePlaylist(_ playlistId: String, isSignedIn: Bool) async {
        try? await client.deletePlaylist(playlistId: playlistId)
        await load(isSignedIn: isSignedIn)
    }
}
