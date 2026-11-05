//
//  PlaylistCoordinator.swift
//  YT Music
//
//  App-level glue for the "Add to Playlist" flow. Right-click menus live all
//  over the app (Home cards, track rows, the now-playing bar), so, like
//  `Navigator`, the intent to add a track is hoisted here and the sheet is
//  presented once at the app shell.
//

import SwiftUI

@MainActor
@Observable
final class PlaylistCoordinator {
    private(set) var pending: PendingAdd?

    struct PendingAdd: Identifiable {
        let id = UUID()
        var videoId: String
        var title: String
    }

    func requestAdd(videoId: String, title: String) {
        pending = PendingAdd(videoId: videoId, title: title)
    }

    func dismiss() { pending = nil }
}
