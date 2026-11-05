//
//  HistoryViewModel.swift
//  YT Music
//

import SwiftUI

@MainActor
@Observable
final class HistoryViewModel {
    enum State {
        case signedOut
        case loading
        case loaded([HistorySection])
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
            let sections = try await client.history()
            state = sections.isEmpty
                ? .failed("You haven't listened to anything yet.")
                : .loaded(sections)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    var canClear: Bool {
        guard case .loaded(let sections) = state else { return false }
        return sections.contains { section in section.tracks.contains { $0.feedbackToken != nil } }
    }

    func remove(_ track: Track) async {
        guard let token = track.feedbackToken, case .loaded(var sections) = state else { return }
        for index in sections.indices {
            sections[index].tracks.removeAll { $0.id == track.id }
        }
        sections.removeAll { $0.tracks.isEmpty }
        state = sections.isEmpty ? emptyState : .loaded(sections)
        try? await client.removeHistoryItems(feedbackTokens: [token])
    }

    func clearAll() async {
        guard case .loaded(let sections) = state else { return }
        let tokens = sections.flatMap { $0.tracks.compactMap(\.feedbackToken) }
        guard !tokens.isEmpty else { return }
        state = emptyState
        try? await client.removeHistoryItems(feedbackTokens: tokens)
    }

    private var emptyState: State { .failed("You haven't listened to anything yet.") }
}
