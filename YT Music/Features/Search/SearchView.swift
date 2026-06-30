//
//  SearchView.swift
//  YT Music
//
//  The Search tab: a search field over YouTube Music's `search` endpoint, with
//  results grouped into category shelves. Song/video shelves render as compact
//  rows (tap to play); album/artist/playlist shelves render as artwork cards.
//  Owns its own navigation stack for pushing entity pages.
//

import SwiftUI

struct SearchView: View {
    @State private var model = SearchViewModel()
    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16, alignment: .top)]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchField
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, showsFilters ? 12 : 16)

                    if showsFilters {
                        filterChips
                            .padding(.bottom, 12)
                    }

                    results
                }
            }
            .navigationTitle("Search")
            .navigationDestination(for: EntityDestination.self) { destination in
                EntityView(destination: destination)
            }
        }
        .task(id: query) {
            // Debounce keystrokes: this task is cancelled and restarted on every
            // change to `query`, so a short sleep coalesces rapid typing.
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.clear()
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await model.search(query)
        }
        .onAppear { fieldFocused = true }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Songs, albums, artists, playlists…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .foregroundStyle(.white)
                .focused($fieldFocused)
                .onSubmit { Task { await model.search(query) } }

            if !query.isEmpty {
                Button {
                    query = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.1))
        .clipShape(.rect(cornerRadius: 10))
    }

    // MARK: - Filter chips

    /// Chips show once a search is underway (any state but the idle prompt), so
    /// the user can scope an existing query to one result type.
    private var showsFilters: Bool {
        if case .idle = model.state { return false }
        return true
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchFilter.allCases) { filter in
                    FilterChip(title: filter.title, selected: filter == model.filter) {
                        Task { await model.apply(filter) }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        switch model.state {
        case .idle:
            prompt(
                icon: "magnifyingglass",
                title: "Search YouTube Music",
                message: "Find songs, albums, artists, and playlists."
            )

        case .loading:
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Spacer()

        case .results(let shelves):
            shelfList(shelves)

        case .empty(let term):
            prompt(
                icon: "questionmark.circle",
                title: "No results for “\(term)”",
                message: "Check the spelling or try a different search."
            )

        case .failed(let message):
            errorView(message)
        }
    }

    private func shelfList(_ shelves: [HomeShelf]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(shelves) { shelf in
                    section(shelf)
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func section(_ shelf: HomeShelf) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)

            if isTrackShelf(shelf) {
                VStack(spacing: 0) {
                    ForEach(shelf.items) { item in
                        SearchResultRow(item: item)
                    }
                }
                .padding(.horizontal, 16)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(shelf.items) { item in
                        ItemCard(item: item)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    /// A shelf renders as a row list when every entry is a playable song/video
    /// (e.g. the "Songs" category), otherwise as an artwork-card grid.
    private func isTrackShelf(_ shelf: HomeShelf) -> Bool {
        shelf.items.allSatisfy { $0.kind == .song || $0.kind == .video }
    }

    // MARK: - States

    private func prompt(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await model.search(query) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            Spacer()
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A pill-shaped search filter toggle. Selected = solid white, otherwise a faint
/// translucent fill.
private struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(selected ? Color.black : Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(selected ? Color.white : Color.white.opacity(0.12))
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// A compact song/video result row: tap to play it as a one-off. Mirrors the
/// entity-page track row but sourced from a search `HomeItem`.
private struct SearchResultRow: View {
    @Environment(PlayerState.self) private var player
    let item: HomeItem

    @State private var hovering = false

    private var links: [EntityLink] {
        item.artists + (item.albumLink.map { [$0] } ?? [])
    }

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(url: item.thumbnailURL, circular: item.prefersCircularArtwork, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                subtitle
            }

            Spacer(minLength: 8)

            if hovering {
                Image(systemName: "play.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(hovering ? Color.white.opacity(0.06) : .clear)
        .clipShape(.rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        // Whole-row tap plays; the inline artist/album links below intercept
        // their own taps to navigate instead.
        .onTapGesture { play() }
        .musicContextMenu(
            title: item.title,
            subtitle: item.subtitle,
            thumbnailURL: item.thumbnailURL,
            videoId: item.videoId,
            playlistId: item.playlistId,
            browseId: item.browseId,
            artists: item.artists,
            albumLink: item.albumLink
        )
    }

    /// Clickable artist/album links when the row carries them, else plain text.
    @ViewBuilder
    private var subtitle: some View {
        if !links.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(links.enumerated()), id: \.offset) { index, link in
                    if index > 0 {
                        Text("•").font(.caption).foregroundStyle(.secondary)
                    }
                    SearchLink(link: link)
                }
            }
            .lineLimit(1)
        } else if !item.subtitle.isEmpty {
            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func play() {
        guard let videoId = item.videoId else { return }
        player.play(
            title: item.title,
            subtitle: item.subtitle,
            thumbnailURL: item.thumbnailURL,
            videoId: videoId
        )
    }
}

/// A single artist/album link in a search row: navigates within the Search
/// stack, turning white and underlined on hover to read as clickable.
private struct SearchLink: View {
    let link: EntityLink

    @State private var hovering = false

    var body: some View {
        NavigationLink(value: link.destination) {
            Text(link.name)
                .font(.caption)
                .foregroundStyle(hovering ? Color.white : Color.secondary)
                .underline(hovering)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(link.name)
    }
}

#Preview {
    SearchView()
        .environment(PlayerState())
        .environment(AuthStore())
        .environment(Navigator())
        .frame(width: 900, height: 600)
}
