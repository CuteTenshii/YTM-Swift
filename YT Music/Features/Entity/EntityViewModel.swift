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
            state = .loaded(page)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
