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

    /// Opens an artist/album page: switch to Home and push the destination onto
    /// its (app-level) navigation path. Works from anywhere — the now-playing
    /// bar, a context menu in Library, etc.
    func open(_ destination: EntityDestination) {
        section = .home
        homePath = [destination]
    }
}
