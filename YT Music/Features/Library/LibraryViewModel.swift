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
}
