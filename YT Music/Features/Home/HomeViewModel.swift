//
//  HomeViewModel.swift
//  YT Music
//

import SwiftUI

@MainActor
@Observable
final class HomeViewModel {
    enum State {
        case idle
        case loading
        case loaded(HomeFeed)
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
            let feed = try await client.homeFeed()
            state = feed.shelves.isEmpty
                ? .failed("No content was returned.")
                : .loaded(feed)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
