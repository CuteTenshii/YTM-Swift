//
//  PageTitle.swift
//  YT Music
//

import SwiftUI

/// Page name in the toolbar, song as the window title. Apply after the page's `.toolbar`.
private struct PageTitle: ViewModifier {
    @Environment(PlayerState.self) private var player
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(windowTitle)
            .scrollEdgeEffectHidden(true, for: .top)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .overlay(alignment: .top) {
                // Blurs whatever scrolls under the toolbar.
                Color.clear
                    .frame(height: 0)
                    .background(.ultraThinMaterial, ignoresSafeAreaEdges: .top)
                    .allowsHitTesting(false)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        // Lines up with where the native toolbar title starts.
                        .padding(.leading, 16)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarSpacer(.flexible)
            }
    }

    /// "Artist - Title", or the app name when nothing plays.
    private var windowTitle: String {
        guard let nowPlaying = player.nowPlaying else { return "YouTube Music" }
        let artist = player.nowPlayingArtist
        return artist.isEmpty ? nowPlaying.title : "\(artist) - \(nowPlaying.title)"
    }
}

extension View {
    func pageTitle(_ title: String) -> some View {
        modifier(PageTitle(title: title))
    }
}
