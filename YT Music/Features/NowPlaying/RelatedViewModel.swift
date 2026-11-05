//
//  RelatedViewModel.swift
//  YT Music
//

import SwiftUI

@MainActor
@Observable
final class RelatedViewModel {
    enum State {
        case idle
        case loading
        case loaded([Shelf])
        case unavailable
        case failed(String)
    }

    private(set) var state: State = .idle

    private let client: RelatedProviding
    private var currentVideoId: String?

    init(client: RelatedProviding = InnerTubeClient.shared) {
        self.client = client
    }

    func load(videoId: String?) async {
        guard let videoId else { state = .unavailable; return }
        currentVideoId = videoId
        state = .loading
        do {
            let shelves = try await client.related(for: videoId)
            guard currentVideoId == videoId else { return }
            state = shelves.isEmpty ? .unavailable : .loaded(shelves)
        } catch {
            guard currentVideoId == videoId else { return }
            state = .failed(error.localizedDescription)
        }
    }
}
