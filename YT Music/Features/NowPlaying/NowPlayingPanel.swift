//
//  NowPlayingPanel.swift
//  YT Music
//
//  The right-hand inspector beside the main content: a segmented switch between
//  the play queue (reorderable, tap to jump, swipe/right-click to remove), the
//  current track's lyrics, and its comments. Toggled from the now-playing bar.
//

import SwiftUI

/// Which page the now-playing inspector is showing.
enum NowPlayingPanelTab: String, CaseIterable, Identifiable {
    case queue = "Queue"
    case lyrics = "Lyrics"
    case related = "Related"
    case comments = "Comments"

    var id: Self { self }
    var icon: String {
        switch self {
        case .queue:    "list.bullet"
        case .lyrics:   "quote.bubble"
        case .related:  "square.stack"
        case .comments: "text.bubble"
        }
    }
}

struct NowPlayingPanelView: View {
    let player: PlayerState
    @Binding var tab: NowPlayingPanelTab
    /// Opens an artist/album page (the panel lives outside the nav stack).
    let navigate: (EntityDestination) -> Void
    /// Shared comments loader (owned by the app shell). Loaded here so the
    /// Comments tab can be hidden when the track has no comments.
    let comments: CommentsViewModel

    /// The tabs offered right now — Comments is dropped when the current track
    /// has no comments.
    private var availableTabs: [NowPlayingPanelTab] {
        comments.isUnavailable
            ? NowPlayingPanelTab.allCases.filter { $0 != .comments }
            : NowPlayingPanelTab.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(availableTabs) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            switch tab {
            case .queue:
                QueueListView(player: player, navigate: navigate)
            case .lyrics:
                LyricsView(player: player,
                           videoId: player.nowPlaying?.videoId,
                           title: player.nowPlaying?.title ?? "",
                           artist: player.nowPlayingArtist,
                           album: player.nowPlaying?.album ?? "",
                           duration: player.duration > 0 ? player.duration : nil)
            case .related:
                RelatedView(videoId: player.nowPlaying?.videoId,
                            title: player.nowPlaying?.title ?? "",
                            artist: player.nowPlayingArtist,
                            album: player.nowPlaying?.album ?? "",
                            duration: player.duration > 0 ? player.duration : nil,
                            player: player,
                            navigate: navigate)
            case .comments:
                CommentsView(videoId: player.nowPlaying?.videoId, model: comments)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .inspectorColumnWidth(min: 280, ideal: 320, max: 440)
        // Probe comments whenever the track changes so the tab reflects whether
        // the new track has any (the panel is only built while the inspector is
        // open, so this doesn't fire for users who never open it).
        .task(id: player.nowPlaying?.videoId) {
            await comments.load(videoId: player.nowPlaying?.videoId)
        }
        // If the playing track loses comments while that tab is selected, fall
        // back to the queue (the segment is about to disappear).
        .onChange(of: comments.isUnavailable) { _, unavailable in
            if unavailable, tab == .comments { tab = .queue }
        }
    }
}

// MARK: - Queue

private struct QueueListView: View {
    let player: PlayerState
    let navigate: (EntityDestination) -> Void

    var body: some View {
        if player.queue.isEmpty {
            ContentUnavailableView(
                "Queue is empty",
                systemImage: "music.note.list",
                description: Text("Play a song, album, or start a radio to build up a queue.")
            )
        } else {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, track in
                    QueueRow(track: track, isCurrent: index == player.currentIndex)
                        .contentShape(.rect)
                        .onTapGesture { player.playQueueItem(at: index) }
                        .contextMenu {
                            Button {
                                player.playQueueItem(at: index)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            if let videoId = track.videoId {
                                Button {
                                    player.startRadio(
                                        title: track.title,
                                        subtitle: track.subtitle,
                                        thumbnailURL: track.thumbnailURL,
                                        videoId: videoId,
                                        artists: track.artists,
                                        albumLink: track.albumLink
                                    )
                                } label: {
                                    Label("Start radio", systemImage: "antenna.radiowaves.left.and.right")
                                }
                            }
                            if !track.artists.isEmpty, let artist = track.artists.first {
                                Button {
                                    navigate(artist.destination)
                                } label: {
                                    Label("Go to artist", systemImage: "music.mic")
                                }
                            }
                            if let album = track.albumLink {
                                Button {
                                    navigate(album.destination)
                                } label: {
                                    Label("Go to album", systemImage: "square.stack")
                                }
                            }
                            Divider()
                            Button(role: .destructive) {
                                player.removeFromQueue(at: index)
                            } label: {
                                Label("Remove from queue", systemImage: "minus.circle")
                            }
                        }
                }
                .onMove { player.moveInQueue(fromOffsets: $0, toOffset: $1) }
                .onDelete { offsets in
                    // Remove high-to-low so earlier removals don't shift the rest.
                    for index in offsets.sorted(by: >) { player.removeFromQueue(at: index) }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct QueueRow: View {
    let track: Track
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ArtworkView(url: track.thumbnailURL, size: 40)
                if isCurrent {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.black.opacity(0.45))
                        .frame(width: 40, height: 40)
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.red : Color.primary)
                    .lineLimit(1)
                let subtitle = PlayerState.withoutTypeLabel(track.subtitle)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let duration = track.duration {
                Text(duration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Lyrics

private struct LyricsView: View {
    let player: PlayerState
    let videoId: String?
    let title: String
    let artist: String
    let album: String
    let duration: Double?
    @Environment(AppSettings.self) private var settings
    @State private var model = LyricsViewModel()

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let lyrics):
                if lyrics.isSynced {
                    SyncedLyricsScroller(player: player, lines: lyrics.lines,
                                         source: lyrics.source, style: .panel)
                } else {
                    PlainLyricsView(lyrics: lyrics)
                }

            case .unavailable:
                ContentUnavailableView(
                    "No lyrics",
                    systemImage: "quote.bubble",
                    description: Text(videoId == nil
                        ? "Play a track to see its lyrics."
                        : "No lyrics from \(settings.lyricsProvider.label) for this track.")
                )

            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load lyrics", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") {
                        Task { await model.load(query: query, provider: settings.lyricsProvider) }
                    }
                }
            }
        }
        // Reload whenever the playing track or the chosen provider changes.
        .task(id: taskKey) { await model.load(query: query, provider: settings.lyricsProvider) }
    }

    private var query: LyricsQuery? {
        guard let videoId else { return nil }
        return LyricsQuery(videoId: videoId, title: title, artist: artist,
                           album: album, duration: duration)
    }

    /// Keyed on the track and provider only — not the duration — so a duration
    /// arriving mid-load doesn't retrigger the fetch.
    private var taskKey: String { "\(videoId ?? "")|\(settings.lyricsProvider.rawValue)" }
}

// MARK: - Related

/// The current track's related music: shelves of similar songs, artists, and
/// recommended playlists (YT Music's "Related" tab), preceded by an on-device
/// "About this song" insight card when Apple Intelligence is available. Because
/// the inspector lives outside the nav stack, cards navigate via the `navigate`
/// closure rather than a `NavigationLink`, and play songs directly.
private struct RelatedView: View {
    let videoId: String?
    let title: String
    let artist: String
    let album: String
    let duration: Double?
    let player: PlayerState
    /// Opens an artist/album/playlist page (the panel lives outside the nav stack).
    let navigate: (EntityDestination) -> Void
    @State private var model = RelatedViewModel()
    @State private var insight = SongInsightViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if insight.isSupported {
                    SongInsightCard(model: insight)
                }
                shelves
            }
            .padding(.vertical, 12)
        }
        .task(id: videoId) { await model.load(videoId: videoId) }
        .task(id: videoId) { await insight.load(query: insightQuery) }
    }

    /// The related shelves, or an inline status while they load / when absent.
    @ViewBuilder
    private var shelves: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)

        case .loaded(let shelves):
            ForEach(shelves) { shelf in
                RelatedShelfView(shelf: shelf, onSelect: select)
            }

        case .unavailable:
            ContentUnavailableView(
                "No related music",
                systemImage: "square.stack",
                description: Text(videoId == nil
                    ? "Play a track to see related music."
                    : "There's no related music for this track.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)

        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load related music", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await model.load(videoId: videoId) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }

    /// The lyrics query the insight is generated from (nil when nothing plays).
    private var insightQuery: LyricsQuery? {
        guard let videoId else { return nil }
        return LyricsQuery(videoId: videoId, title: title, artist: artist,
                           album: album, duration: duration)
    }

    /// A browsable item (album/playlist/artist) opens its page; a song/video
    /// plays. Items that are neither do nothing.
    private func select(_ item: HomeItem) {
        if let destination = item.entityDestination {
            navigate(destination)
        } else if let videoId = item.videoId {
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
}

/// An on-device "About this song" card. Shows a spinner while generating, the
/// insight when ready, and nothing at all when there are no lyrics to work from
/// or generation fails — an auxiliary feature shouldn't clutter the tab.
private struct SongInsightCard: View {
    let model: SongInsightViewModel

    var body: some View {
        switch model.state {
        case .idle, .unavailable, .failed:
            EmptyView()

        case .loading:
            shell {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the lyrics…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

        case .loaded(let insight):
            shell {
                VStack(alignment: .leading, spacing: 10) {
                    Text(insight.summary)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !insight.mood.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Mood")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(insight.mood)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }

                    if !insight.themes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(insight.themes, id: \.self) { theme in
                                    Text(theme)
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.tint.opacity(0.18), in: Capsule())
                                }
                            }
                        }
                    }

                    Text("Generated on your Mac from the lyrics — may be imperfect.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// The card chrome: a titled, softly-filled rounded box.
    @ViewBuilder
    private func shell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("About this song", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }
}

/// One related shelf: its title, then its items as a wrapping card grid (like
/// YT Music's Related tab). The grid adapts its column count to the panel width.
private struct RelatedShelfView: View {
    let shelf: HomeShelf
    let onSelect: (HomeItem) -> Void

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 16, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.title)
                .font(.headline)
                .padding(.horizontal, 16)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(shelf.items) { item in
                    RelatedCard(item: item) { onSelect(item) }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// A single related item card: artwork above its title and subtitle. Mirrors
/// Home's `ItemCard` layout, but taps run the panel's select closure (play or
/// navigate) instead of a `NavigationLink`, which is inert outside the nav stack.
private struct RelatedCard: View {
    let item: HomeItem
    let onSelect: () -> Void

    private let artworkSize: CGFloat = 132

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkView(url: item.thumbnailURL,
                            circular: item.prefersCircularArtwork,
                            size: artworkSize)

                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                let subtitle = PlayerState.withoutTypeLabel(item.subtitle)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(width: artworkSize, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Comments

private struct CommentsView: View {
    let videoId: String?
    /// Shared loader, driven by the panel (so the tab's availability is known
    /// before this view is shown). This view only renders its state.
    let model: CommentsViewModel

    /// The reply thread being viewed, if any. Driven by local state rather than a
    /// `NavigationStack`: the inspector already lives in a window whose toolbar
    /// hosts the detail column's navigation back button, and a second
    /// `NavigationStack` here would try to register a duplicate
    /// `com.apple.SwiftUI.navigationStack.back` item and crash AppKit's toolbar.
    @State private var thread: Comment?

    var body: some View {
        if let thread {
            CommentThreadView(comment: thread, model: model,
                              onBack: { self.thread = nil })
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.comments) { comment in
                        CommentRow(comment: comment) { thread = comment }
                        Divider()
                    }
                    if model.canLoadMore {
                        LoadMoreFooter { await model.loadMore() }
                    }
                }
                .padding(.vertical, 4)
            }

        case .unavailable:
            ContentUnavailableView(
                "No comments",
                systemImage: "text.bubble",
                description: Text(videoId == nil
                    ? "Play a track to see its comments."
                    : "Comments aren't available for this track.")
            )

        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load comments", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await model.load(videoId: videoId) }
                }
            }
        }
    }
}

/// A row in the top-level list: the comment, plus a link into its replies.
private struct CommentRow: View {
    let comment: Comment
    /// Opens this comment's reply thread.
    let onOpenThread: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentContentView(comment: comment)

            if comment.replyToken != nil {
                Button(action: onOpenThread) {
                    HStack(spacing: 4) {
                        Text(repliesLabel)
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .padding(.leading, 42)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var repliesLabel: String {
        if let count = comment.replyCount { return "View \(count) replies" }
        return "View replies"
    }
}

/// The replies sub-view: the parent comment pinned on top, then its (paginated)
/// replies.
private struct CommentThreadView: View {
    let comment: Comment
    let model: CommentsViewModel
    /// Returns to the top-level comments list.
    let onBack: () -> Void

    @State private var replies: [Comment] = []
    @State private var nextToken: String?
    @State private var isLoading = true
    @State private var isLoadingMore = false

    var body: some View {
        VStack(spacing: 0) {
            // Self-contained back control: this view is presented via local
            // state (not a NavigationStack), so it owns its own way back.
            HStack(spacing: 4) {
                Button(action: onBack) {
                    Label("Comments", systemImage: "chevron.left")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    CommentContentView(comment: comment)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                Divider()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }

                ForEach(replies) { reply in
                    CommentContentView(comment: reply)
                        .padding(.leading, 20)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    Divider()
                }

                if nextToken != nil {
                    LoadMoreFooter { await loadMore() }
                }
                }
                .padding(.vertical, 4)
            }
        }
        .task {
            guard isLoading else { return }
            let page = await model.replyPage(for: comment, after: nil)
            replies = page.replies
            nextToken = page.next
            isLoading = false
        }
    }

    private func loadMore() async {
        guard let token = nextToken, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let page = await model.replyPage(for: comment, after: token)
        replies.append(contentsOf: page.replies)
        nextToken = page.next
    }
}

/// A spinner that runs `load` when it scrolls into view — the infinite-scroll
/// trigger. `onAppear` fires once per appearance (re-firing when scrolled back
/// to), so the loader only needs to guard against overlapping calls.
private struct LoadMoreFooter: View {
    let load: () async -> Void

    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .onAppear { Task { await load() } }
    }
}

/// One comment's avatar, author line, body, and like/reply counts. Shared by
/// top-level rows and (indented) replies.
private struct CommentContentView: View {
    let comment: Comment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ArtworkView(url: comment.authorThumbnailURL, circular: true, size: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(comment.author)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if comment.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if let time = comment.publishedTime {
                        Text(time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(comment.text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                HStack(spacing: 14) {
                    if let likes = comment.likeCount {
                        Label(likes, systemImage: "hand.thumbsup")
                    }
                    if let replies = comment.replyCount {
                        Label(replies, systemImage: "bubble.left")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

