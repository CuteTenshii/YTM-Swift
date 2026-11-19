//
//  SearchView.swift
//  YT Music
//
//  The reusable search surface over YouTube Music's `search` endpoint, with
//  results grouped into category shelves. Song/video shelves render as compact
//  rows (tap to play); album/artist/playlist shelves render as artwork cards.
//  It is embedded by HomeView and uses the surrounding navigation stack.
//

import SwiftUI

struct SearchContent: View {
    @State private var model = SearchViewModel()
    let query: String
    @FocusState private var focusedItem: ShelfItem.ID?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16, alignment: .top)]

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                if showsFilters {
                    filterChips
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                }

                results
            }
        }
        .task(id: query) {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.clear()
                return
            }
            await model.search(query)
        }
    }

    // MARK: - Filter chips

    private var showsFilters: Bool {
        if case .idle = model.state { return false }
        return true
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchFilter.allCases) { filter in
                    FilterChip(title: filter.title, isSelected: filter == model.filter) {
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
        case .idle, .loading:
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(.primary)
            Spacer()

        case .results(let shelves):
            shelfList(shelves)

        case .empty(let term):
            prompt(
                icon: "questionmark.circle",
                title: String(format: String(localized: "search.empty.title"), term),
                message: "search.empty.message"
            )

        case .failed(let message):
            errorView(message)
        }
    }

    private func shelfList(_ shelves: [Shelf]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(shelves) { shelf in
                        section(shelf)
                    }
                }
                .padding(.vertical, 8)
                .padding(.bottom, 24)
            }
            .rowArrowNavigation($focusedItem,
                                ids: shelves.filter(isTrackShelf).flatMap { $0.items.map(\.id) },
                                proxy: proxy)
        }
    }

    @ViewBuilder
    private func section(_ shelf: Shelf) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 24)

            if isTrackShelf(shelf) {
                VStack(spacing: 0) {
                    ForEach(shelf.items) { item in
                        SearchResultRow(item: item)
                            .focused($focusedItem, equals: item.id)
                            .id(item.id)
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

    private func isTrackShelf(_ shelf: Shelf) -> Bool {
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
                .foregroundStyle(.primary)
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
            Button("common.retry") {
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

private struct SearchResultRow: View {
    @Environment(PlayerState.self) private var player
    let item: ShelfItem

    @State private var hovering = false

    private var links: [EntityLink] {
        item.artists + (item.albumLink.map { [$0] } ?? [])
    }

    private var isCurrent: Bool {
        item.videoId != nil && item.videoId == player.nowPlaying?.videoId
    }

    var body: some View {
        HStack(spacing: 14) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.body)
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .foregroundStyle(isCurrent ? Color.red : .primary)
                        .lineLimit(1)
                    if item.isExplicit {
                        ExplicitBadge()
                    }
                }
                subtitle
            }

            Spacer(minLength: 8)

            if let duration = item.duration {
                Text(duration)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .clipShape(.rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        // Inline artist/album links intercept their own taps.
        .onTapGesture { play() }
        .playableRow(play)
        .musicContextMenu(
            title: item.title,
            subtitle: item.subtitle,
            thumbnailURL: item.thumbnailURL,
            videoId: item.videoId,
            playlistId: item.playlistId,
            browseId: item.browseId,
            artists: item.artists,
            albumLink: item.albumLink,
            likeStatus: item.likeStatus
        )
    }

    private var artwork: some View {
        ZStack {
            ArtworkView(url: item.thumbnailURL, circular: item.prefersCircularArtwork, size: 44)
            if isCurrent || hovering {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.45))
                    .frame(width: 44, height: 44)
                Image(systemName: isCurrent ? "speaker.wave.2.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

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
            videoId: videoId,
            artists: item.artists,
            albumLink: item.albumLink
        )
    }
}

private struct ExplicitBadge: View {
    var body: some View {
        Text(verbatim: "E")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(Color.appBackground)
            .frame(width: 13, height: 13)
            .background(.secondary, in: .rect(cornerRadius: 3))
            .accessibilityLabel(Text("search.explicit"))
    }
}

private struct SearchLink: View {
    let link: EntityLink

    @State private var hovering = false

    var body: some View {
        NavigationLink(value: link.destination) {
            Text(link.name)
                .font(.caption)
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .underline(hovering)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(link.name)
    }
}

#Preview {
    SearchContent(query: "")
        .environment(PlayerState())
        .environment(AuthStore())
        .environment(Navigator())
        .frame(width: 900, height: 600)
}
