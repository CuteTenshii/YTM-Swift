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
    var failure: ActionFailure?

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
                ? .failed(String(localized: "history.empty"))
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
        guard let token = track.feedbackToken, case .loaded(let previous) = state else { return }
        var sections = previous
        for index in sections.indices {
            sections[index].tracks.removeAll { $0.id == track.id }
        }
        sections.removeAll { $0.tracks.isEmpty }
        state = sections.isEmpty ? emptyState : .loaded(sections)
        await commitRemoval(of: [token], restoring: previous, title: String(localized: "history.remove.failed"))
    }

    func clearAll() async {
        guard case .loaded(let previous) = state else { return }
        let tokens = previous.flatMap { $0.tracks.compactMap(\.feedbackToken) }
        guard !tokens.isEmpty else { return }
        state = emptyState
        await commitRemoval(of: tokens, restoring: previous, title: String(localized: "history.clear.failed"))
    }

    private func commitRemoval(of tokens: [String], restoring previous: [HistorySection], title: String) async {
        do {
            try await client.removeHistoryItems(feedbackTokens: tokens)
        } catch {
            state = .loaded(previous)
            failure = ActionFailure(title: title, error: error)
        }
    }

    private var emptyState: State { .failed(String(localized: "history.empty")) }
}
