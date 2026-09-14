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
        case loaded([HomeShelf])
        case failed(String)
    }

    private(set) var state: State = .loading

    private let client: InnerTubeClient

    init(client: InnerTubeClient = .shared) {
        self.client = client
    }

    func load(isSignedIn: Bool) async {
        guard isSignedIn else {
            state = .signedOut
            return
        }
        state = .loading
        do {
            let shelves = try await client.library()
            state = shelves.isEmpty
                ? .failed("Your library is empty.")
                : .loaded(shelves)
        } catch {
            state = .failed(error.localizedDescription)
        }
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
