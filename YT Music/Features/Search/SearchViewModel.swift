//
//  SearchViewModel.swift
//  YT Music
//

import SwiftUI

@MainActor
@Observable
final class SearchViewModel {
    enum State {
        case idle
        case loading
        case results([Shelf])
        case empty(String)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var suggestions: [String] = []
    private(set) var filter: SearchFilter = .all

    private let client: InnerTubeClient
    private var query = ""

    init(client: InnerTubeClient = .shared) {
        self.client = client
    }

    func clear() {
        state = .idle
        suggestions = []
        filter = .all
        query = ""
    }

    func loadSuggestions(for input: String) async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            return
        }
        do {
            let values = try await client.searchSuggestions(trimmed)
            guard !Task.isCancelled else { return }
            suggestions = Array(values.prefix(8))
        } catch {
            guard !Task.isCancelled else { return }
            suggestions = []
        }
    }

    func search(_ query: String) async {
        filter = .all
        self.query = query
        await run()
    }

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
