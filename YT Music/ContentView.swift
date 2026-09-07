//
//  ContentView.swift
//  YT Music
//
//  App shell: a YT Music–style sidebar, a persistent now-playing bar, and a
//  queue/lyrics inspector that slides in from the right.
//

import SwiftUI

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case home = "Home"
        case explore = "Explore"
        case search = "Search"
        case library = "Library"
        case uploads = "Uploads"
        case history = "History"
        case settings = "Settings"

        var id: Self { self }

        var icon: String {
            switch self {
            case .home:     "house.fill"
            case .explore:  "square.grid.2x2.fill"
            case .search:   "magnifyingglass"
            case .library:  "books.vertical.fill"
            case .uploads:  "square.and.arrow.up.fill"
            case .history:  "clock.arrow.circlepath"
            case .settings: "gearshape.fill"
            }
        }
    }

    @Environment(PlayerState.self) private var player
    @Environment(AuthStore.self) private var auth
    @Environment(Navigator.self) private var navigator
    @Environment(PlaylistCoordinator.self) private var playlists

    /// Shared comments loader: drives both the panel's Comments tab and whether
    /// the now-playing bar's Comments button is enabled.
    @State private var comments = CommentsViewModel()

    var body: some View {
        @Bindable var auth = auth
        @Bindable var navigator = navigator

        ZStack {
            VStack(spacing: 0) {
                if auth.sessionExpired {
                    SessionExpiredBanner(auth: auth)
                }

                NavigationSplitView {
                    List(Section.allCases, selection: $navigator.section) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                    }
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        AccountControl(auth: auth)
                    }
                } detail: {
                    switch navigator.section {
                    case .home:
                        HomeView()
                    case .explore:
                        ExploreView()
                    case .search:
                        SearchView()
                    case .library:
                        LibraryView()
                    case .uploads:
                        UploadsView()
                    case .history:
                        HistoryView()
                    case .settings:
                        SettingsView()
                    }
                }
                .inspector(isPresented: $navigator.showingPanel) {
                    NowPlayingPanelView(player: player, tab: $navigator.panelTab,
                                        navigate: navigator.open, comments: comments)
                }

                // Docked transport bar: a permanent full-width row, never an overlay.
                if player.nowPlaying != nil {
                    NowPlayingBar(
                        player: player,
                        isSignedIn: auth.isSignedIn,
                        navigate: navigator.open,
                        showingPanel: $navigator.showingPanel,
                        panelTab: $navigator.panelTab,
                        showingImmersiveLyrics: $navigator.showingImmersiveLyrics,
                        comments: comments
                    )
                }
            }
            // The window toolbar (sidebar toggle + navigation title) is drawn in
            // the titlebar. Hide it while the immersive view is up so nothing
            // floats over the full-window overlay.
            .toolbar(navigator.showingImmersiveLyrics ? .hidden : .automatic, for: .windowToolbar)

            // The immersive view is a sibling layer (not an `.overlay` on the
            // inset content) so `.ignoresSafeArea()` can bleed it edge-to-edge —
            // otherwise the menu-bar / notch region stays black in full screen.
            // A GeometryReader captures the top inset (read before ignoring it)
            // so the header can still clear the notch.
            if navigator.showingImmersiveLyrics {
                GeometryReader { geo in
                    ImmersiveLyricsView(player: player,
                                        isPresented: $navigator.showingImmersiveLyrics,
                                        safeAreaTop: geo.safeAreaInsets.top)
                        .ignoresSafeArea()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .sheet(isPresented: $auth.isPresentingLogin) {
            LoginView()
                .environment(auth)
        }
        .sheet(isPresented: playlistSheetBinding) {
            if let add = playlists.pending {
                AddToPlaylistSheet(add: add) { playlists.dismiss() }
            }
        }
    }

    /// Presents the "Add to Playlist" picker while the coordinator has a pending
    /// track (dismissing clears it).
    private var playlistSheetBinding: Binding<Bool> {
        Binding(get: { playlists.pending != nil }, set: { if !$0 { playlists.dismiss() } })
    }
}

/// A slim warning bar shown when the signed-in session has expired (a 401 came
/// back), prompting the user to sign in again.
private struct SessionExpiredBanner: View {
    let auth: AuthStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.black)
            Text("Your session expired. Sign in again to restore your library and playback.")
                .foregroundStyle(.black)
                .font(.callout.weight(.medium))
            Spacer(minLength: 8)
            Button("Sign in") { auth.isPresentingLogin = true }
                .buttonStyle(.borderedProminent)
                .tint(.black)
            Button {
                auth.dismissExpiredNotice()
            } label: {
                Image(systemName: "xmark").foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.yellow)
    }
}

/// Sidebar footer: sign in, or a menu to sign out.
private struct AccountControl: View {
    let auth: AuthStore

    var body: some View {
        Group {
            switch auth.state {
            case .unknown:
                ProgressView().controlSize(.small)
            case .signedOut:
                Button {
                    auth.isPresentingLogin = true
                } label: {
                    Label("Sign in", systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .signedIn:
                Menu {
                    Button("Sign out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                } label: {
                    signedInLabel
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var signedInLabel: some View {
        HStack(spacing: 8) {
            avatar
            VStack(alignment: .leading, spacing: 1) {
                Text(auth.account?.name ?? "Signed in")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if let handle = auth.account?.handle, !handle.isEmpty {
                    Text(handle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var avatar: some View {
        CachedAsyncImage(url: auth.account?.avatarURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
        .frame(width: 16, height: 16)
        .clipShape(.circle)
        .fixedSize()
    }
}

/// Persistent transport bar reflecting the current track and playback state.
private struct NowPlayingBar: View {
    let player: PlayerState
    /// Whether the user is signed in (the like action requires a session).
    let isSignedIn: Bool
    /// Opens an artist/album page (the bar lives outside the nav stack).
    let navigate: (EntityDestination) -> Void
    /// Drives the queue/lyrics inspector visibility and selected page.
    @Binding var showingPanel: Bool
    @Binding var panelTab: NowPlayingPanelTab
    /// Opens the immersive full-window lyrics view.
    @Binding var showingImmersiveLyrics: Bool
    /// Comments loader, so the Comments button can disable when there are none.
    let comments: CommentsViewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(.white.opacity(0.1))
            HStack(spacing: 16) {
                // Left and right clusters share a fixed width so the transport
                // controls between the two Spacers stay truly centered.
                HStack(spacing: 14) {
                    trackInfo
                    if isSignedIn {
                        likeButton
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: sideWidth, alignment: .leading)

                Spacer(minLength: 12)

                // Transport controls sit directly above the scrubber.
                VStack(spacing: 6) {
                    transportControls
                    scrubber
                }
                .frame(maxWidth: 520)

                Spacer(minLength: 12)

                HStack(spacing: 16) {
                    Spacer(minLength: 0)
                    volumeControl
                        .frame(width: 130)
                    immersiveLyricsButton
                    panelButton(.lyrics)
                    panelButton(.comments)
                    panelButton(.queue)
                }
                .frame(width: sideWidth, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    /// Opens the immersive, full-window lyrics view.
    private var immersiveLyricsButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { showingImmersiveLyrics = true }
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Full-screen lyrics")
    }

    /// Toggles the queue/lyrics inspector: opens it to `tab`, or closes it if
    /// that page is already showing.
    private func panelButton(_ tab: NowPlayingPanelTab) -> some View {
        let active = showingPanel && panelTab == tab
        return Button {
            if active {
                showingPanel = false
            } else {
                panelTab = tab
                showingPanel = true
            }
        } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Color.red : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(tab == .comments && comments.isUnavailable)
        .help(tab.rawValue)
    }

    /// Equal width reserved for the track-info (left) and volume (right)
    /// clusters, so the centered transport block lands at the true midpoint.
    private let sideWidth: CGFloat = 300

    // MARK: - Track info (with clickable artists / album)

    @ViewBuilder
    private var trackInfo: some View {
        if let nowPlaying = player.nowPlaying {
            HStack(spacing: 12) {
                ArtworkView(url: nowPlaying.thumbnailURL, size: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    subtitle(nowPlaying)
                }
            }
        }
    }

    /// The artist/album line: shows an error or loading message, then clickable
    /// links when we have them, otherwise the plain subtitle text.
    @ViewBuilder
    private func subtitle(_ nowPlaying: PlayerState.NowPlaying) -> some View {
        if let error = player.loadError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        } else if player.isLoading {
            Text("Loading…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if !nowPlaying.artists.isEmpty {
            // Only use the clickable links row when we actually have artist links.
            // A track whose artist is plain text (no channel page) but whose album
            // is linked would otherwise render as a stray "• Album" with the artist
            // name dropped — fall through to the full subtitle text instead.
            linksRow(artists: nowPlaying.artists, album: nowPlaying.albumLink)
        } else {
            let text = PlayerState.withoutTypeLabel(nowPlaying.subtitle)
            Text(text.isEmpty ? "—" : text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Artists are comma-separated; the album (if any) follows after a bullet —
    /// matching YT Music's own "Artist, Artist • Album" convention.
    ///
    /// Layout priority decreases left-to-right so an over-long line truncates
    /// from the right as a whole (album first, then trailing artists) instead of
    /// each link getting its own ellipsis the way independent `lineLimit(1)`
    /// children in an HStack otherwise would.
    private func linksRow(artists: [EntityLink], album: EntityLink?) -> some View {
        let total = artists.count + (album == nil ? 0 : 1)
        return HStack(spacing: 0) {
            ForEach(Array(artists.enumerated()), id: \.offset) { index, link in
                if index > 0 {
                    Text(", ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                EntityLinkButton(link: link) { navigate(link.destination) }
                    .layoutPriority(Double(total - index))
            }
            if let album {
                Text(" • ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                EntityLinkButton(link: album) { navigate(album.destination) }
                    .layoutPriority(0)
            }
        }
        .lineLimit(1)
    }

    // MARK: - Like

    private var likeButton: some View {
        let liked = player.likeStatus == .liked
        return Button(action: player.toggleLike) {
            Image(systemName: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(liked ? Color.red : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(player.isUpdatingLike)
        .help(liked ? "Remove from liked songs" : "Like")
    }

    // MARK: - Transport

    private var transportControls: some View {
        HStack(spacing: 18) {
            Button(action: player.toggleShuffle) {
                Image(systemName: "shuffle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(shuffleTint)
            }
            .buttonStyle(.plain)
            .disabled(player.queue.isEmpty)
            .help("Shuffle")

            Button(action: player.previous) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(player.canGoPrevious ? Color.white : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!player.canGoPrevious)

            playButton

            Button(action: player.next) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(player.canGoNext ? Color.white : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!player.canGoNext)

            Button(action: player.cycleRepeatMode) {
                Image(systemName: repeatIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.red)
            }
            .buttonStyle(.plain)
            .help("Repeat")
        }
    }

    private var repeatIcon: String {
        switch player.repeatMode {
        case .off, .all: "repeat"
        case .one:       "repeat.1"
        }
    }

    private var shuffleTint: Color {
        if player.queue.isEmpty { return .secondary }
        return player.isShuffled ? .red : .secondary
    }

    @ViewBuilder
    private var playButton: some View {
        if player.isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(width: 36, height: 36)
        } else {
            Button(action: player.togglePlayPause) {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(player.loadError != nil)
        }
    }

    // MARK: - Volume

    private var volumeControl: some View {
        @Bindable var player = player
        return HStack(spacing: 8) {
            Image(systemName: volumeIcon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Slider(value: $player.volume, in: 0...1)
                .controlSize(.small)
                .tint(.white)
        }
    }

    private var volumeIcon: String {
        switch player.volume {
        case ..<0.01: "speaker.slash.fill"
        case ..<0.5:  "speaker.wave.1.fill"
        default:      "speaker.wave.2.fill"
        }
    }

    // MARK: - Scrubber

    @ViewBuilder
    private var scrubber: some View {
        if player.duration > 0 {
            HStack(spacing: 8) {
                Text(timeString(player.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                SeekBar(
                    currentTime: player.currentTime,
                    bufferedTime: player.bufferedTime,
                    duration: player.duration,
                    onSeek: { player.seek(to: $0) }
                )

                Text(timeString(player.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            // Keep the row height stable before a duration is known.
            Color.clear.frame(height: 11)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A single artist/album link in the now-playing bar: secondary text that turns
/// white and underlines on hover to read as clickable.
private struct EntityLinkButton: View {
    let link: EntityLink
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
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

/// A custom playback scrubber that shows played progress (red), cached/buffered
/// progress (lighter fill), and the remaining track, with a draggable thumb.
/// Replaces a plain Slider so the "cache progress" can sit behind the playhead.
struct SeekBar: View {
    let currentTime: Double
    let bufferedTime: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var dragTime: Double?

    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 11

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let played = dragTime ?? currentTime

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(width: width * fraction(bufferedTime), height: trackHeight)

                Capsule()
                    .fill(.red)
                    .frame(width: width * fraction(played), height: trackHeight)

                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: width * fraction(played) - thumbSize / 2)
            }
            .frame(height: thumbSize)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragTime = time(at: value.location.x, width: width)
                    }
                    .onEnded { value in
                        onSeek(time(at: value.location.x, width: width))
                        dragTime = nil
                    }
            )
        }
        .frame(height: thumbSize)
    }

    private func fraction(_ time: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(time / duration, 0), 1)
    }

    private func time(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1) * duration
    }
}

#Preview {
    ContentView()
        .environment(PlayerState())
        .environment(AuthStore())
        .environment(Navigator())
        .environment(PlaylistCoordinator())
        .environment(AppSettings())
        .frame(width: 1000, height: 700)
}
