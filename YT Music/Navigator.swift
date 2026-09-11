//
//  Navigator.swift
//  YT Music
//
//  App-level navigation routing. The now-playing bar and right-click menus live
//  outside (or below) every tab's NavigationStack, so to open an artist/album
//  from them we hoist both the selected sidebar section and a navigation path
//  per section here. `open(_:)` pushes a destination onto whichever tab is on
//  screen; each section binds its stack to its path (which survives tab switches).
//

import SwiftUI

@MainActor
@Observable
final class Navigator {
    /// The selected sidebar section (the app shell binds the sidebar to this).
    var section: ContentView.Section = .home

    /// One navigation path per browsable section. Each section's `NavigationStack`
    /// binds to its own path here (rather than owning a private `@State` path), so
    /// that (a) navigation survives tab switches, and (b) `open(_:)` can push onto
    /// whichever tab is currently on screen. Settings has no stack.
    var homePath: [EntityDestination] = []
    var explorePath: [EntityDestination] = []
    var libraryPath: [EntityDestination] = []
    var uploadsPath: [EntityDestination] = []
    var historyPath: [EntityDestination] = []

    /// Whether the right-hand queue/lyrics/comments inspector is open, and which
    /// page it shows. Hoisted here (from ContentView's local state) so menu-bar
    /// commands can toggle the panel too.
    var showingPanel = false
    var panelTab: NowPlayingPanelTab = .queue
    /// Whether the immersive full-window lyrics view is showing.
    var showingImmersiveLyrics = false

    /// Pushes an artist/album page onto the stack of the tab currently on screen,
    /// so navigation triggered from outside/below the stacks — the now-playing
    /// bar, a right-click "Go to album/artist", the queue list — stays in the
    /// user's current tab instead of silently pushing onto an off-screen Home
    /// stack. Settings has no stack, so fall back to Home.
    ///
    /// We *append* rather than replace the path. Replacing a non-empty path with
    /// another non-empty path of the same length (e.g. `[A]` → `[B]`, clicking a
    /// second artist while already on an artist page) is a NavigationStack update
    /// SwiftUI on macOS silently drops — the page wouldn't change until you went
    /// back and emptied the path. Pushing always grows the path, so it applies
    /// reliably and leaves a working back stack. Guard against re-pushing the page
    /// already on top.
    func open(_ destination: EntityDestination) {
        if section == .settings { section = .home }
        switch section {
        case .explore: append(destination, to: &explorePath)
        case .library: append(destination, to: &libraryPath)
        case .uploads: append(destination, to: &uploadsPath)
        case .history: append(destination, to: &historyPath)
        case .home, .settings: append(destination, to: &homePath)
        }
    }

    private func append(_ destination: EntityDestination, to path: inout [EntityDestination]) {
        guard path.last != destination else { return }
        path.append(destination)
    }

    /// The navigation path of the section currently on screen (its last entry is
    /// the page being displayed). Lets "go to" actions disable themselves when
    /// they'd re-open the page already showing.
    var currentPath: [EntityDestination] {
        switch section {
        case .explore: explorePath
        case .library: libraryPath
        case .uploads: uploadsPath
        case .history: historyPath
        case .home, .settings: homePath
        }
    }

    /// Toggles the inspector to `tab`: opens it there, or closes it if that page
    /// is already showing.
    func togglePanel(_ tab: NowPlayingPanelTab) {
        if showingPanel && panelTab == tab {
            showingPanel = false
        } else {
            panelTab = tab
            showingPanel = true
        }
    }
}
