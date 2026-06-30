//
//  SearchViewModel.swift
//  YT Music
//

import SwiftUI

@MainActor
@Observable
final class SearchViewModel {
    enum State {
        case idle                   // no query yet — show the prompt
        case loading
        case results([HomeShelf])
        case empty(String)          // query returned nothing
        case failed(String)
    }

    private(set) var state: State = .idle
    /// The active filter chip. Reset to `.all` whenever a fresh query is typed.
    private(set) var filter: SearchFilter = .all

    private let client: InnerTubeClient
    /// The last non-empty query, so a filter change can re-run it.
    private var query = ""

    init(client: InnerTubeClient = .shared) {
        self.client = client
    }

    /// Resets to the idle prompt (called when the field is cleared).
    func clear() {
        state = .idle
        filter = .all
        query = ""
    }

    /// Runs a search for a newly typed query. Resets any active filter so the
    /// chips start on "All" for each new search. The caller debounces and cancels
    /// the surrounding task on each keystroke, so we bail if cancelled before
    /// publishing results.
    func search(_ query: String) async {
        filter = .all
        self.query = query
        await run()
    }

    /// Re-runs the current query scoped to `filter`. No-op if unchanged or there's
    /// no query yet.
    func apply(_ filter: SearchFilter) async {
        guard filter != self.filter else { return }
        self.filter = filter
        await run()
    }

    private func run() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { state = .idle; return }

        state = .loading
        do {
            let shelves = try await client.search(trimmed, filter: filter)
            guard !Task.isCancelled else { return }
            state = shelves.isEmpty ? .empty(trimmed) : .results(shelves)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error.localizedDescription)
        }
    }
}
