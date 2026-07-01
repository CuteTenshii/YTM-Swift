//
//  Navigator.swift
//  YT Music
//
//  App-level navigation routing. The now-playing bar and right-click menus live
//  outside (or below) every tab's NavigationStack, so to open an artist/album
//  from them we hoist both the selected sidebar section and the Home tab's
//  navigation path here. `open(_:)` switches to Home and pushes a destination;
//  HomeView binds its stack to this path (which survives tab switches).
//

import SwiftUI

@MainActor
@Observable
final class Navigator {
    /// The selected sidebar section (the app shell binds the sidebar to this).
    var section: ContentView.Section = .home
    /// The Home tab's navigation path.
    var homePath: [EntityDestination] = []

    /// Whether the right-hand queue/lyrics/comments inspector is open, and which
    /// page it shows. Hoisted here (from ContentView's local state) so menu-bar
    /// commands can toggle the panel too.
    var showingPanel = false
    var panelTab: NowPlayingPanelTab = .queue
    /// Whether the immersive full-window lyrics view is showing.
    var showingImmersiveLyrics = false

    /// Opens an artist/album page: switch to Home and push the destination onto
    /// its (app-level) navigation path. Works from anywhere — the now-playing
    /// bar, a context menu in Library, etc.
    ///
    /// We *append* rather than replace the path. Replacing a non-empty path with
    /// another non-empty path of the same length (e.g. `[A]` → `[B]`, clicking a
    /// second artist while already on an artist page) is a NavigationStack update
    /// SwiftUI on macOS silently drops — the page wouldn't change until you went
    /// back and emptied the path. Pushing always grows the path, so it applies
    /// reliably and leaves a working back stack. Guard against re-pushing the page
    /// already on top.
    func open(_ destination: EntityDestination) {
        section = .home
        guard homePath.last != destination else { return }
        homePath.append(destination)
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
