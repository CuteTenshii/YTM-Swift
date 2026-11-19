//
//  HomeView.swift
//  YT Music
//
//  The Home tab: a vertical stack of horizontally-scrolling shelves, rendered
//  from the live YouTube Music `FEmusic_home` feed. Owns the navigation stack
//  that pushes album/playlist/artist pages.
//

import SwiftUI

struct HomeView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(Navigator.self) private var navigator
    @Environment(PlayerState.self) private var player
    @State private var model = HomeViewModel()
    @State private var searchModel = SearchViewModel()
    @State private var searchText = ""
    @State private var submittedQuery = ""
    @State private var selectedChip: FeedChip?

    var body: some View {
        @Bindable var navigator = navigator

        NavigationStack(path: $navigator.homePath) {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                switch model.state {
                case .idle, .loading:
                    ProgressView("home.loading")
                        .controlSize(.large)
                        .tint(.primary)
                        .foregroundStyle(.primary)

                case .loaded(let feed):
                    if !submittedQuery.isEmpty {
                        SearchContent(query: submittedQuery)
                    } else {
                        feedContent(feed)
                    }

                case .failed(let message):
                    errorView(message)
                }
            }
            .pageTitle(String(localized: "home.title"))
            .navigationDestination(for: EntityDestination.self) { destination in
                EntityView(destination: destination)
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "search.prompt")
            .searchSuggestions {
                ForEach(searchModel.suggestions.queries, id: \.self) { suggestion in
                    Text(suggestion)
                        .searchCompletion(suggestion)
                }
                ForEach(searchModel.suggestions.items) { item in
                    Button { open(item) } label: { suggestionRow(item) }
                }
            }
            .onSubmit(of: .search) { submittedQuery = searchText }
        }
        .task(id: auth.generation) { await model.load() }
        .task(id: searchText) {
            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                submittedQuery = ""
                searchModel.clear()
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await searchModel.loadSuggestions(for: searchText)
        }
    }

    // MARK: - Suggestions

    private func suggestionRow(_ item: ShelfItem) -> some View {
        HStack(spacing: 10) {
            ArtworkView(url: item.thumbnailURL, circular: item.prefersCircularArtwork, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func open(_ item: ShelfItem) {
        if let videoId = item.videoId {
            player.play(
                title: item.title,
                subtitle: item.subtitle,
                thumbnailURL: item.thumbnailURL,
                videoId: videoId,
                artists: item.artists,
                albumLink: item.albumLink
            )
        } else if let destination = item.entityDestination {
            navigator.open(destination)
        }
    }

    // MARK: - Feed

    private func feedContent(_ feed: HomeFeed) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if !feed.chips.isEmpty {
                    chipRow(feed.chips)
                }

                ForEach(feed.shelves) { shelf in
                    ShelfView(shelf: shelf)
                }

                if let continuation = feed.continuation {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .task(id: continuation) { await model.loadMore() }
                }
            }
            .padding(.vertical, 24)
        }
    }

    private func chipRow(_ chips: [FeedChip]) -> some View {
        FilterChipRow(chips: chips, title: \.title, selection: selectedChip, showsAll: false) { chip in
            selectedChip = chip
            Task { await model.load(chip: chip, inPlace: true) }
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("home.load_failed")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("common.retry") {
                Task { await model.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(40)
        .frame(maxWidth: 380)
    }
}

#Preview {
    HomeView()
        .environment(PlayerState())
        .environment(AuthStore())
        .environment(Navigator())
        .frame(width: 900, height: 600)
}
