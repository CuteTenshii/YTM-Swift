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
    var section: ContentView.Section = .home

    var homePath: [EntityDestination] = []
    var explorePath: [EntityDestination] = []
    var libraryPath: [EntityDestination] = []
    var uploadsPath: [EntityDestination] = []
    var historyPath: [EntityDestination] = []

    var showingPanel = false
    var panelTab: NowPlayingPanelTab = .queue
    var showingImmersiveLyrics = false
    var creditsRequest: SongCreditsRequest?

    /// Appends (never replaces) the path: SwiftUI on macOS drops same-length path replacements.
    func open(_ destination: EntityDestination) {
        switch section {
        case .explore: append(destination, to: &explorePath)
        case .library: append(destination, to: &libraryPath)
        case .uploads: append(destination, to: &uploadsPath)
        case .history: append(destination, to: &historyPath)
        case .home: append(destination, to: &homePath)
        }
    }

    private func append(_ destination: EntityDestination, to path: inout [EntityDestination]) {
        guard path.last != destination else { return }
        path.append(destination)
    }

    func goBack() {
        switch section {
        case .explore: if !explorePath.isEmpty { explorePath.removeLast() }
        case .library: if !libraryPath.isEmpty { libraryPath.removeLast() }
        case .uploads: if !uploadsPath.isEmpty { uploadsPath.removeLast() }
        case .history: if !historyPath.isEmpty { historyPath.removeLast() }
        case .home: if !homePath.isEmpty { homePath.removeLast() }
        }
    }

    var currentPath: [EntityDestination] {
        switch section {
        case .explore: explorePath
        case .library: libraryPath
        case .uploads: uploadsPath
        case .history: historyPath
        case .home: homePath
        }
    }

    func togglePanel(_ tab: NowPlayingPanelTab) {
        if showingPanel && panelTab == tab {
            showingPanel = false
        } else {
            panelTab = tab
            showingPanel = true
        }
    }
}
