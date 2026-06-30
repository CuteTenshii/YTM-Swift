//
//  ExploreViewModel.swift
//  YT Music
//

import SwiftUI

@MainActor
@Observable
final class ExploreViewModel {
    enum State {
        case idle
        case loading
        case loaded([HomeShelf])
        case failed(String)
    }

    private(set) var state: State = .idle

    private let client: InnerTubeClient

    init(client: InnerTubeClient = .shared) {
        self.client = client
    }

    func loadIfNeeded() async {
        if case .loaded = state { return }
        await load()
    }

    func load() async {
        state = .loading
        do {
            let shelves = try await client.explore()
            state = shelves.isEmpty
                ? .failed("No content was returned.")
                : .loaded(shelves)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
