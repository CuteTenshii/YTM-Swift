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
    /// True once the header has scrolled up under the titlebar — flips the
    /// window toolbar from transparent (immersive) to its blurred background.
    @State private var scrolledUnderBar = false
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
        .navigationTitle(model.title)
        // Let the artwork gradient bleed up under the window titlebar while the
        // header is in view; once scrolled past it, restore the blurred bar so
        // the back button + title stay legible over the track list. Dark scheme
        // keeps those controls light in both states.
        .toolbarBackground(scrolledUnderBar ? .visible : .hidden, for: .windowToolbar)
        .toolbarColorScheme(.dark, for: .windowToolbar)
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
        // Re-check subscription state when auth changes (sign-in/out) or the page
        // is revisited, so the subscribe button reflects the server, not a stale
        // optimistic value.
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
        // Tracks played from an album page carry the album name into Now Playing.
        let album = page.header.kind == .album ? page.header.title : ""
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let visibleTracks: [Track]
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            visibleTracks = page.tracks
        } else {
            visibleTracks = searchResults ?? []
        }

        // Read the titlebar inset, then let the scroll content ignore it so the
        // header gradient bleeds under the (transparent) window toolbar. The
        // header pads itself back down by that inset to clear the back button.
        // A List rather than a ScrollView so playlist tracks reorder like the queue.
        return GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top

            List {
                if page.isFeed {
                    // A bare feed (a shelf's "More"): skip the album-style
                    // artwork header, just title the page above its shelves,
                    // whose cards wrap into a grid rather than scrolling.
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
                    HeaderView(header: page.header, tracks: page.tracks,
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
            .ignoresSafeArea(.container, edges: .top)
            // Flip the toolbar background once the tinted header has mostly
            // scrolled out of view, animating the transition.
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y > topInset + 140
            } action: { _, past in
                withAnimation(.easeInOut(duration: 0.25)) { scrolledUnderBar = past }
            }
        }
    }

    /// The track rows, or the loading / empty state in their place.
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

    /// The numbered track rows, draggable to reorder when the playlist allows
    /// it, followed by a sentinel that loads the next page.
    @ViewBuilder
    private func trackRows(_ tracks: [Track], album: String, isSearching: Bool, hasMore: Bool) -> some View {
        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
            VStack(spacing: 0) {
                TrackRow(track: track, index: index, tracks: tracks, album: album,
                         canRemove: model.editablePlaylistId != nil, onRemove: removeTrack)
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

    /// Removes a playlist row via the model, then drops it from any live search
    /// results so both listings stay in sync.
    private func removeTrack(_ track: Track) {
        Task {
            if await model.removeFromPlaylist(track) {
                searchResults = searchResults?.filter { $0.id != track.id }
            }
        }
    }

    /// Drag-to-reorder for rows, unless the list is a search result or the
    /// playlist can't be reordered.
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
    /// A full-width List row without inset, separator, or background, so the
    /// page reads like a plain scroll view.
    func plainListRow() -> some View {
        // Cancels the macOS table's built-in 17pt cell spacing (8 + 9), which
        // zero insets and content margins leave in place.
        listRowInsets(EdgeInsets(top: 0, leading: -8, bottom: 0, trailing: -9))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// A page section: a plain List row followed by the gap between sections.
    func sectionSpacing() -> some View {
        padding(.bottom, 28).plainListRow()
    }
}

// MARK: - Loading skeleton

/// Placeholder mirroring the loaded layout — header (artwork + text bars +
/// buttons) above a list of track rows — so the page keeps its shape while the
/// entity loads, instead of a bare spinner.
private struct EntitySkeleton: View {
    /// Artist pages use circular artwork; albums/playlists a rounded square.
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
        // Vary the title width per row so the list doesn't read as a uniform grid.
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
    let album: String
    let model: EntityViewModel
    /// Height of the window titlebar the header extends under, so its content
    /// can be padded down to clear the back button while the gradient bleeds up.
    let topInset: CGFloat

    /// Prominent colours pulled from the cover art, driving the header gradient.
    @State private var palette: [PaletteColor] = []
    /// Edit-sheet / delete-confirmation state for the edit menu.
    @State private var editingPlaylist = false
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if header.kind == .artist, let banner = header.bannerURL {
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
                privacy: header.privacy,
                save: { name, description, privacy in
                    await model.editPlaylist(name: name, description: description, privacy: privacy)
                },
                onFinish: { editingPlaylist = false }
            )
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

    /// The default header: circular/square artwork beside title, subtitle,
    /// description, and the action buttons, over a gradient tinted to the art.
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
                    Text(header.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
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

    /// The album artist(s) or playlist owner: avatar plus linked names.
    private func bylineRow(_ byline: EntityByline) -> some View {
        let font = Font.callout.weight(.semibold)
        return HStack(spacing: 8) {
            if let avatar = byline.avatarURL {
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

    /// A vertical wash built from the two most prominent cover-art colours,
    /// fading to clear at the bottom so it melts into the page and the
    /// track list below. Fills the header's frame (which the ScrollView extends
    /// under the titlebar), so the tint reaches the window's top edge.
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

    /// Scales a palette colour so its brightest channel hits `brightness`,
    /// preserving hue. Unlike `adjusted(brightness:)` (which only darkens), this
    /// also lifts dark, muddy tints — the common case for dim cover art — into a
    /// vivid wash that actually reads over the page.
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

    /// Fetches the cover art and extracts its palette off the main actor.
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

    /// Full-bleed artist banner: the wide artwork fills the width, fading into
    /// the page at the bottom, with the title and actions overlaid.
    private func bannerHeader(_ url: URL) -> some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.primary.opacity(0.06)
                }
            }
            .frame(height: 360)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.appBackground.opacity(0.35), Color.appBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

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

                if !header.description.isEmpty {
                    Text(header.description)
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.75))
                        .lineLimit(3)
                }

                actions
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The action-button row (play / subscribe / save / download), shared by
    /// both header layouts.
    @ViewBuilder
    private var actions: some View {
        if !tracks.isEmpty || showsSubscribe || showsSave || header.radioPlaylistId != nil {
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

                if let radioPlaylistId = header.radioPlaylistId {
                    Button {
                        player.playAll(videoId: nil, playlistId: radioPlaylistId)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
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

    /// Whether to offer the subscribe toggle: artist pages, signed in, with a
    /// subscribe button parsed from the header.
    private var showsSubscribe: Bool {
        header.kind == .artist && auth.isSignedIn && model.subscription != nil
    }

    /// Whether to offer the "Save to library" toggle: playlist pages, signed in.
    private var showsSave: Bool {
        auth.isSignedIn && model.savablePlaylistId != nil
    }

    /// Whether to offer playlist editing (rename / delete): one of the signed-in
    /// user's own playlists, per the row `setVideoId` signal.
    private var showsEditMenu: Bool {
        auth.isSignedIn && model.isEditablePlaylist
    }

    /// The page's official share URL once loaded, else one built from its ids.
    private var link: URL? {
        if case .loaded(let page) = model.state, let url = page.shareURL { return url }
        return MusicLinks.url(
            videoId: nil,
            playlistId: model.savablePlaylistId,
            browseId: model.destination.browseId
        )
    }

    /// Overflow menu for an owned playlist: metadata editing and deletion.
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

    /// The owned-playlist edit affordances, shared by the "More" menu and the
    /// header's right-click menu.
    @ViewBuilder
    private var editActions: some View {
        Button {
            editingPlaylist = true
        } label: {
            Label("Edit Playlist…", systemImage: "square.and.pencil")
        }
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Label("Delete Playlist…", systemImage: "trash")
        }
    }

    /// Subscribe / Subscribed toggle for artist pages.
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

    /// Save / Saved toggle for playlist pages ("Add to library").
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

    /// The download button's title; nil on pages that aren't a collection.
    private var downloadTitle: String? {
        switch header.kind {
        case .album:    "Download album"
        case .playlist: "Download playlist"
        default:        nil
        }
    }

    /// Live batch progress while a multi-track download runs.
    private var downloadProgress: String? {
        guard case .running(let progress) = downloader.status, progress.total > 1 else { return nil }
        return "Downloading \(progress.index)/\(progress.total)…"
    }
}
