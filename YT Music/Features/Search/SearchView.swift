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
    @State private var width: CGFloat = 0

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

        case .results(let results):
            resultList(results)

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

    private func resultList(_ results: SearchResults) -> some View {
        let rowIds = (results.topResult?.tracks ?? []).map(\.id)
            + results.shelves.filter(isTrackShelf).flatMap { $0.items.map(\.id) }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if let topResult = results.topResult {
                        topSection(topResult)
                    }
                    ForEach(results.shelves) { shelf in
                        section(shelf)
                    }
                }
                .padding(.vertical, 8)
                .padding(.bottom, 24)
            }
            .rowArrowNavigation($focusedItem, ids: rowIds, proxy: proxy)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func topSection(_ result: SearchTopResult) -> some View {
        let layout = width >= 820
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle(String(localized: "search.top_result"))
                .padding(.horizontal, 24)

            layout {
                TopResultCard(result: result)
                if !result.tracks.isEmpty {
                    trackRows(result.tracks)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title2.weight(.bold))
            .foregroundStyle(.primary)
    }

    private func trackRows(_ items: [ShelfItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                SearchResultRow(item: item)
                    .focused($focusedItem, equals: item.id)
                    .id(item.id)
            }
        }
    }

    @ViewBuilder
    private func section(_ shelf: Shelf) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(shelf.title)
                .padding(.horizontal, 24)

            if isTrackShelf(shelf) {
                trackRows(shelf.items)
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

private struct TopResultCard: View {
    @Environment(PlayerState.self) private var player
    let result: SearchTopResult

    private var item: ShelfItem { result.item }

    var body: some View {
        HStack(spacing: 20) {
            opener {
                ArtworkView(url: item.thumbnailURL, circular: item.prefersCircularArtwork, size: 120)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    opener {
                        Text(item.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if item.isExplicit {
                        ExplicitBadge()
                    }
                }
                Text(item.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    ForEach(Array(result.actions.enumerated()), id: \.element) { index, action in
                        actionButton(action, prominent: index == 0)
                    }
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
        .musicContextMenu(
            title: item.title,
            subtitle: item.subtitle,
            thumbnailURL: item.thumbnailURL,
            videoId: item.videoId,
            playlistId: item.playlistId,
            browseId: item.browseId,
            artists: item.artists,
            albumLink: item.albumLink,
            entityDestination: item.entityDestination,
            likeStatus: item.likeStatus
        )
    }

    /// Entities open their page; songs and videos play.
    @ViewBuilder
    private func opener<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        if let destination = item.entityDestination {
            NavigationLink(value: destination, label: label)
                .buttonStyle(.plain)
        } else if item.videoId != nil {
            Button(action: playItem, label: label)
                .buttonStyle(.plain)
        } else {
            label()
        }
    }

    @ViewBuilder
    private func actionButton(_ action: SearchTopResult.Action, prominent: Bool) -> some View {
        let button = Button { run(action) } label: {
            Label(title(for: action), systemImage: icon(for: action))
                .font(.headline)
                .padding(.horizontal, 8)
        }
        if prominent {
            button.buttonStyle(.borderedProminent).tint(.red)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func title(for action: SearchTopResult.Action) -> LocalizedStringKey {
        switch action {
        case .play: "common.play"
        case .shuffle: "common.shuffle"
        case .mix: "entity.mix"
        }
    }

    private func icon(for action: SearchTopResult.Action) -> String {
        switch action {
        case .play: "play.fill"
        case .shuffle: "shuffle"
        case .mix: "dot.radiowaves.left.and.right"
        }
    }

    private func run(_ action: SearchTopResult.Action) {
        switch action {
        case .play(let videoId, let playlistId?):
            player.playAll(videoId: videoId, playlistId: playlistId)
        case .play:
            playItem()
        case .shuffle(let playlistId):
            player.playAll(videoId: nil, playlistId: playlistId, shuffled: true)
        case .mix(let playlistId):
            player.playAll(videoId: nil, playlistId: playlistId)
        }
    }

    private func playItem() {
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
