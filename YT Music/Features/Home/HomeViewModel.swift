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
    private(set) var isLoadingChip = false

    private let client: InnerTubeClient

    init(client: InnerTubeClient = .shared) {
        self.client = client
    }

    func loadIfNeeded() async {
        if case .loaded = state { return }
        await load()
    }

    func load(chip: HomeChip? = nil) async {
        let isChipLoad = chip != nil
        if isChipLoad {
            isLoadingChip = true
        } else {
            state = .loading
        }
        defer {
            if isChipLoad { isLoadingChip = false }
        }

        do {
            let feed = try await client.homeFeed(
                browseId: chip?.browseId ?? "FEmusic_home",
                params: chip?.params
            )
            if feed.shelves.isEmpty {
                if !isChipLoad { state = .failed("No content was returned.") }
            } else {
                state = .loaded(feed)
            }
        } catch {
            if !isChipLoad {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
