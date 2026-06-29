//
//  ContentView.swift
//  YT Music
//
//  App shell: a YT Music–style sidebar plus a persistent now-playing bar.
//  Only Home is wired end-to-end for now; the other destinations are placeholders.
//

import SwiftUI

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case home = "Home"
        case explore = "Explore"
        case library = "Library"

        var id: Self { self }

        var icon: String {
            switch self {
            case .home:    "house.fill"
            case .explore: "square.grid.2x2.fill"
            case .library: "books.vertical.fill"
            }
        }
    }

    @Environment(PlayerState.self) private var player
    @Environment(AuthStore.self) private var auth
    @Binding var selection: Section

    var body: some View {
        @Bindable var auth = auth

        VStack(spacing: 0) {
            NavigationSplitView {
                List(Section.allCases, selection: $selection) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    AccountControl(auth: auth)
                }
            } detail: {
                switch selection {
                case .home:
                    HomeView()
                case .library:
                    LibraryView()
                case .explore:
                    placeholder(selection)
                }
            }

            // Docked transport bar: a permanent full-width row, never an overlay.
            if player.nowPlaying != nil {
                NowPlayingBar(player: player)
            }
        }
        .sheet(isPresented: $auth.isPresentingLogin) {
            LoginView()
                .environment(auth)
        }
    }

    private func placeholder(_ section: Section) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("\(section.rawValue) coming soon")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
        }
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
        AsyncImage(url: auth.account?.avatarURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
        .frame(width: 20, height: 20)
        .clipShape(.circle)
    }
}

/// Persistent transport bar reflecting the current track and playback state.
private struct NowPlayingBar: View {
    let player: PlayerState

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(.white.opacity(0.1))
            HStack(spacing: 14) {
                if let nowPlaying = player.nowPlaying {
                    ArtworkView(url: nowPlaying.thumbnailURL, size: 52)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowPlaying.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(subtitleText(nowPlaying))
                            .font(.caption)
                            .foregroundStyle(player.loadError == nil ? Color.secondary : Color.red)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 160, alignment: .leading)
                }

                Spacer(minLength: 8)

                scrubber

                Spacer(minLength: 8)

                transportControls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private func subtitleText(_ nowPlaying: PlayerState.NowPlaying) -> String {
        if let error = player.loadError { return error }
        if player.isLoading { return "Loading…" }
        return nowPlaying.subtitle.isEmpty ? "—" : nowPlaying.subtitle
    }

    private var transportControls: some View {
        HStack(spacing: 18) {
            Button(action: player.cycleRepeatMode) {
                Image(systemName: repeatIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.red)
            }
            .buttonStyle(.plain)
            .help("Repeat")

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
        }
    }

    private var repeatIcon: String {
        switch player.repeatMode {
        case .off, .all: "repeat"
        case .one:       "repeat.1"
        }
    }

    @ViewBuilder
    private var playButton: some View {
        if player.isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(width: 40)
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

    @ViewBuilder
    private var scrubber: some View {
        if player.duration > 0 {
            HStack(spacing: 8) {
                Text(timeString(player.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...player.duration
                )
                .frame(maxWidth: 420)
                .tint(.red)

                Text(timeString(player.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview {
    ContentView(selection: .constant(.home))
        .environment(PlayerState())
        .environment(AuthStore())
        .frame(width: 1000, height: 700)
}
