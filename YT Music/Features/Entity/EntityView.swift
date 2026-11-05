//
//  EntityView.swift
//  YT Music
//
//  Detail page for an album, playlist, or artist: a large header, a track
//  listing (albums/playlists), and any carousels (artist albums/related).
//

import SwiftUI
import AppKit

struct EntityView: View {
    @Environment(AuthStore.self) private var auth
    @State private var model: EntityViewModel
    @State private var searchText = ""
    @State private var searchResults: [Track]?
    @State private var searchCompleted = false

    init(destination: EntityDestination) {
        _model = State(initialValue: EntityViewModel(destination: destination))
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            switch model.state {
            case .loading:
                EntitySkeleton(circular: model.destination.kind == .artist || model.destination.kind == .profile)

            case .loaded(let page):
                loadedContent(page)

            case .failed(let message):
                errorView(message)
            }
        }
        .pageTitle(model.title)
        .task { await model.loadIfNeeded() }
        .task(id: searchText) {
            searchResults = nil
            searchCompleted = false
            guard model.destination.kind == .playlist,
                  !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            searchResults = await model.searchPlaylist(searchText)
            searchCompleted = !Task.isCancelled
        }
        .task(id: auth.generation) { await model.revalidateSubscription() }
    }

    // MARK: - Loaded content

    @ViewBuilder
    private func loadedContent(_ page: EntityPage) -> some View {
        if model.destination.kind == .playlist {
            content(page)
                .searchable(text: $searchText, placement: .toolbar, prompt: "Find in playlist")
        } else {
            content(page)
        }
    }

    private func sortMenu(_ options: [PlaylistSortOption]) -> some View {
        let selection = Binding<String>(
            get: { options.first(where: \.isSelected)?.title ?? "" },
            set: { title in
                guard let option = options.first(where: { $0.title == title }) else { return }
                Task { await model.applySort(option) }
            }
        )
        return Picker("Sort", selection: selection) {
            ForEach(options) { option in
                Text(option.title).tag(option.title)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .disabled(model.isReloadingTracks)
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    private func content(_ page: EntityPage) -> some View {
        let album = page.header.kind == .album ? page.header.title : ""
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let visibleTracks: [Track]
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            visibleTracks = page.tracks
        } else {
            visibleTracks = searchResults ?? []
        }

        return GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top

            // List, not ScrollView, so playlist tracks reorder like the queue.
            List {
                if page.isFeed {
                    Text(page.header.title)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 24)
                        .padding(.top, topInset + 16)
                        .sectionSpacing()

                    ForEach(page.shelves) { shelf in
                        ShelfGridView(shelf: shelf, showsHeader: page.shelves.count > 1)
                            .sectionSpacing()
                    }
                } else {
                    HeaderView(header: page.header, tracks: page.tracks, shufflePlaylistId: page.shufflePlaylistId,
                               album: album, model: model, topInset: topInset)
                        .sectionSpacing()

                    if !isSearching && (!page.filters.isEmpty || !page.sortOptions.isEmpty) {
                        HStack(spacing: 12) {
                            if page.filters.isEmpty {
                                Spacer()
                            } else {
                                FilterChipRow(chips: page.filters, title: \.title,
                                              selection: model.selectedFilter) { filter in
                                    Task { await model.applyFilter(filter) }
                                }
                            }
                            if !page.sortOptions.isEmpty {
                                sortMenu(page.sortOptions)
                                    .padding(.trailing, 24)
                            }
                        }
                        .sectionSpacing()
                    }

                    tracksSection(page, tracks: visibleTracks, album: album, isSearching: isSearching)

                    ForEach(page.shelves) { shelf in
                        ShelfView(shelf: shelf)
                            .sectionSpacing()
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            // Header gradient bleeds under the toolbar; the header re-pads by `topInset`.
            .ignoresSafeArea(.container, edges: .top)
        }
    }

    @ViewBuilder
    private func tracksSection(_ page: EntityPage, tracks visibleTracks: [Track],
                               album: String, isSearching: Bool) -> some View {
        if model.isReloadingTracks && !isSearching {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .sectionSpacing()
        } else if !visibleTracks.isEmpty {
            trackRows(visibleTracks, album: album, isSearching: isSearching,
                      hasMore: !isSearching && page.continuationToken != nil)
        } else if isSearching && !searchCompleted {
            ProgressView()
                .controlSize(.small)
                .padding(.horizontal, 24)
                .sectionSpacing()
        } else if isSearching {
            emptyText("No results for \"\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                .sectionSpacing()
        } else if let filter = model.selectedFilter {
            emptyText("No songs for \"\(filter.title)\"")
                .sectionSpacing()
        } else if page.header.kind == .playlist {
            emptyText("This playlist is empty")
                .sectionSpacing()
        }
    }

    @ViewBuilder
    private func trackRows(_ tracks: [Track], album: String, isSearching: Bool, hasMore: Bool) -> some View {
        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
            VStack(spacing: 0) {
                TrackRow(track: track, index: index, tracks: tracks, album: album,
                         canRemove: model.editablePlaylistId != nil, onRemove: removeTrack,
                         onVote: isSearching ? nil : { track, target in Task { await model.vote(track, target) } })
                if index < tracks.count - 1 {
                    Divider().overlay(.primary.opacity(0.08))
                }
            }
            .padding(.horizontal, 24)
            .plainListRow()
        }
        .onMove(perform: moveAction(searching: isSearching))

        if hasMore {
            Color.clear
                .frame(height: 1)
                .id(tracks.count)
                .onAppear { Task { await model.loadMore() } }
                .plainListRow()
        }
        Color.clear
            .frame(height: 28)
            .plainListRow()
    }

    // MARK: - States

    private func removeTrack(_ track: Track) {
        Task {
            if await model.removeFromPlaylist(track) {
                searchResults = searchResults?.filter { $0.id != track.id }
            }
        }
    }

    private func moveAction(searching: Bool) -> ((IndexSet, Int) -> Void)? {
        guard !searching, model.canReorder else { return nil }
        return { source, destination in
            Task { await model.moveTrack(fromOffsets: source, toOffset: destination) }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await model.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding(40)
        .frame(maxWidth: 380)
    }
}

private extension View {
    func plainListRow() -> some View {
        // Cancels the macOS table's built-in 17pt cell spacing.
        listRowInsets(EdgeInsets(top: 0, leading: -8, bottom: 0, trailing: -9))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    func sectionSpacing() -> some View {
        padding(.bottom, 28).plainListRow()
    }
}

// MARK: - Loading skeleton

private struct EntitySkeleton: View {
    let circular: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                trackList
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
        .shimmering()
        .disabled(true)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 24) {
            SkeletonBox(
                width: 200,
                height: 200,
                cornerRadius: circular ? 100 : 8,
                circular: circular
            )

            VStack(alignment: .leading, spacing: 12) {
                SkeletonBox(width: 320, height: 38, cornerRadius: 8)
                SkeletonBox(width: 220, height: 16)
                SkeletonBox(width: 260, height: 12)
                HStack(spacing: 12) {
                    SkeletonBox(width: 96, height: 34, cornerRadius: 8)
                    SkeletonBox(width: 120, height: 34, cornerRadius: 8)
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }

    private var trackList: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { index in
                row(index: index)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                if index < 7 {
                    Divider().overlay(.primary.opacity(0.08))
                }
            }
        }
    }

    private func row(index: Int) -> some View {
        let titleWidths: [CGFloat] = [220, 300, 180, 260, 200, 320, 240, 190]
        return HStack(spacing: 14) {
            SkeletonBox(width: 16, height: 14)
                .frame(width: 28, alignment: .trailing)

            SkeletonBox(width: 40, height: 40, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 6) {
                SkeletonBox(width: titleWidths[index % titleWidths.count], height: 13)
                SkeletonBox(width: 120, height: 11)
            }

            Spacer(minLength: 8)

            SkeletonBox(width: 36, height: 12)
        }
    }
}

// MARK: - Header

private struct HeaderView: View {
    @Environment(PlayerState.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(Downloader.self) private var downloader
    @Environment(AuthStore.self) private var auth
    @Environment(Navigator.self) private var navigator
    let header: EntityHeader
    let tracks: [Track]
    let shufflePlaylistId: String?
    let album: String
    let model: EntityViewModel
    let topInset: CGFloat

    @State private var palette: [PaletteColor] = []
    @State private var editingPlaylist = false
    @State private var confirmingDelete = false
    @State private var collaborating = false

    var body: some View {
        Group {
            if header.kind == .artist, let banner = header.artistPage?.bannerURL {
                bannerHeader(banner)
            } else {
                standardHeader
            }
        }
        .task(id: header.thumbnailURL) { await loadPalette() }
        .contextMenu {
            if showsEditMenu {
                editActions
                Divider()
            }
            if let link {
                ShareLink(item: link)
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(link.absoluteString, forType: .string)
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            }
        }
        .sheet(isPresented: $editingPlaylist) {
            EditPlaylistSheet(
                name: header.title,
                description: header.description,
                privacy: header.collection?.privacy,
                voteOptions: (header.collection?.voteOptions ?? []),
                save: { name, description, privacy, votePermission in
                    await model.editPlaylist(name: name, description: description, privacy: privacy,
                                             votePermission: votePermission)
                },
                onFinish: { editingPlaylist = false }
            )
        }
        .sheet(isPresented: $collaborating) {
            if let playlistId = model.editablePlaylistId {
                CollaborationSheet(
                    playlistId: playlistId,
                    title: header.title,
                    destination: model.destination,
                    onFinish: { collaborating = false }
                )
            }
        }
        .alert("Delete Playlist", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    if await model.deletePlaylist() { navigator.goBack() }
                }
            }
        } message: {
            Text("“\(model.title)” will be permanently deleted.")
        }
    }

    private var standardHeader: some View {
        HStack(alignment: .bottom, spacing: 24) {
            ArtworkView(
                url: header.thumbnailURL,
                circular: header.prefersCircularArtwork,
                size: 200
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(header.title)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                if let byline = header.byline {
                    bylineRow(byline)
                }

                if !header.subtitle.isEmpty {
                    Text(header.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !header.description.isEmpty {
                    DescriptionText(text: header.description)
                }

                actions
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, topInset + 16)
        .padding(.bottom, 20)
        .background(alignment: .top) { artworkGradient }
    }

    private func bylineRow(_ byline: EntityByline) -> some View {
        let font = Font.callout.weight(.semibold)
        return HStack(spacing: 8) {
            if byline.avatarURLs.count > 1 {
                avatarPill(byline.avatarURLs)
            } else if let avatar = byline.avatarURLs.first {
                ArtworkView(url: avatar, circular: true, size: 24)
            }
            HStack(spacing: 0) {
                ForEach(byline.runs.indices, id: \.self) { index in
                    let run = byline.runs[index]
                    if let link = run.link {
                        EntityLinkButton(link: link, font: font) { navigator.open(link.destination) }
                    } else {
                        Text(run.text)
                            .font(font)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .lineLimit(1)
        }
    }

    private func avatarPill(_ urls: [URL]) -> some View {
        HStack(spacing: -8) {
            ForEach(urls, id: \.self) { url in
                ArtworkView(url: url, circular: true, size: 24)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 2))
            }
        }
        .padding(3)
        .background(.quaternary, in: .capsule)
    }

    private var artworkGradient: some View {
        let top = vivid(palette.first, brightness: 0.85)
        let mid = vivid(palette.dropFirst().first ?? palette.first, brightness: 0.7)
        return LinearGradient(
            stops: [
                .init(color: top.opacity(0.85), location: 0),
                .init(color: mid.opacity(0.45), location: 0.55),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .animation(.easeInOut(duration: 0.5), value: palette)
    }

    private func vivid(_ color: PaletteColor?, brightness target: Double) -> Color {
        guard let color else { return Color.primary.opacity(0.12) }
        let mx = max(color.red, color.green, color.blue)
        guard mx > 0 else { return Color(.sRGB, red: target, green: target, blue: target) }
        let k = target / mx
        return Color(.sRGB,
                     red: min(1, color.red * k),
                     green: min(1, color.green * k),
                     blue: min(1, color.blue * k))
    }

    private func loadPalette() async {
        guard let url = header.thumbnailURL else {
            palette = []
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            palette = await Task.detached { ArtworkPalette.extract(from: data) }.value
        } catch {
            palette = []
        }
    }

    private func bannerHeader(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(header.title)
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 2)

            if !header.subtitle.isEmpty {
                Text(header.subtitle)
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.85))
            }

            let meta = [header.artistPage?.monthlyAudience, header.artistPage?.pronouns].compactMap(\.self)
            if !meta.isEmpty {
                Text(meta.joined(separator: " • "))
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.85))
            }

            if !header.description.isEmpty {
                DescriptionText(text: header.description, style: AnyShapeStyle(.primary.opacity(0.75)))
            }

            actions
        }
        .padding(24)
        .padding(.top, topInset)
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .bottomLeading)
        .background {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.primary.opacity(0.06)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.55), location: 0.55),
                        .init(color: Color.appBackground, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    @ViewBuilder
    private var actions: some View {
        if !tracks.isEmpty || showsSubscribe || showsSave || header.artistPage?.radioPlaylistId != nil
            || header.artistPage?.startRadioPlaylistId != nil || shufflePlaylistId != nil {
            HStack(spacing: 12) {
                if !tracks.isEmpty {
                    Button {
                        player.play(tracks, startAt: 0, album: album)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                if let radioPlaylistId = header.artistPage?.radioPlaylistId {
                    Button {
                        player.playAll(videoId: nil, playlistId: radioPlaylistId)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.headline)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.bordered)
                }

                if let shufflePlaylistId {
                    Button {
                        player.playAll(videoId: nil, playlistId: shufflePlaylistId, shuffled: true)
                    } label: {
                        Label("Shuffle all", systemImage: "shuffle")
                            .font(.headline)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.bordered)
                }

                if let mixId = header.artistPage?.startRadioPlaylistId, mixId != header.artistPage?.radioPlaylistId {
                    Button {
                        player.playAll(videoId: nil, playlistId: mixId)
                    } label: {
                        Label("Mix", systemImage: "dot.radiowaves.left.and.right")
                            .font(.headline)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.bordered)
                }

                if showsSubscribe {
                    subscribeButton
                }

                if showsSave {
                    saveButton
                }

                if showsEditMenu {
                    editMenu
                }

                if downloader.isEnabled && !tracks.isEmpty, let downloadTitle {
                    downloadButton(downloadTitle)
                }
            }
            .padding(.top, 6)
        }
    }

    private var showsSubscribe: Bool {
        header.kind == .artist && auth.isSignedIn && model.subscription?.isEnabled == true
    }

    private var showsSave: Bool {
        auth.isSignedIn && model.savablePlaylistId != nil && header.isSaved != nil
    }

    private var showsEditMenu: Bool {
        auth.isSignedIn && model.isEditablePlaylist
    }

    private var link: URL? {
        if case .loaded(let page) = model.state, let url = page.shareURL { return url }
        return MusicLinks.url(
            videoId: nil,
            playlistId: model.savablePlaylistId,
            browseId: model.destination.browseId
        )
    }

    private var editMenu: some View {
        Menu {
            editActions
        } label: {
            Label("More", systemImage: "ellipsis")
                .font(.headline)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var editActions: some View {
        Button {
            editingPlaylist = true
        } label: {
            Label("Edit Playlist…", systemImage: "square.and.pencil")
        }
        Button {
            collaborating = true
        } label: {
            Label("Collaborate…", systemImage: "person.2.badge.plus")
        }
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Label("Delete Playlist…", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var subscribeButton: some View {
        if let subscription = model.subscription {
            Button {
                Task { await model.toggleSubscription() }
            } label: {
                Label(
                    subscription.isSubscribed ? "Subscribed" : "Subscribe",
                    systemImage: subscription.isSubscribed ? "bell.fill" : "bell"
                )
                .font(.headline)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.bordered)
            .tint(subscription.isSubscribed ? .red : nil)
            .disabled(model.isUpdatingSubscription)
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        Button {
            Task { await model.toggleSaved() }
        } label: {
            Label(
                model.isSaved ? "Saved" : "Save to library",
                systemImage: model.isSaved ? "checkmark.circle.fill" : "plus.circle"
            )
            .font(.headline)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.bordered)
        .tint(model.isSaved ? .red : nil)
        .disabled(model.isUpdatingSaved)
    }

    private func downloadButton(_ title: String) -> some View {
        Button {
            downloader.download(
                tracks,
                collection: header.title,
                to: settings.effectiveDownloadDirectory,
                preferences: settings.streamPreferences
            )
        } label: {
            Label(downloadProgress ?? title, systemImage: "arrow.down.circle")
                .font(.headline)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.bordered)
        .disabled(downloader.isBusy)
    }

    private var downloadTitle: String? {
        switch header.kind {
        case .album:    "Download album"
        case .playlist: "Download playlist"
        default:        nil
        }
    }

    private var downloadProgress: String? {
        guard case .running(let progress) = downloader.status, progress.total > 1 else { return nil }
        return "Downloading \(progress.index)/\(progress.total)…"
    }
}
