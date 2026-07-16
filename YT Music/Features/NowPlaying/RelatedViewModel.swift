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
        case loaded([HomeShelf])
        case unavailable
        case failed(String)
    }

    private(set) var state: State = .idle

    private let client: RelatedProviding
    /// The track currently being loaded, so a slow response for a previous track
    /// can't overwrite the state after the user has moved on.
    private var currentVideoId: String?

    init(client: RelatedProviding = InnerTubeClient.shared) {
        self.client = client
    }

    /// Loads the related shelves for the given track. A nil id (nothing playing)
    /// or a track with no related tab resolves to `.unavailable`.
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
