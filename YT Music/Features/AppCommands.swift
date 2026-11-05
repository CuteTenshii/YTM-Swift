//
//  AppCommands.swift
//  YT Music
//
//  Menu-bar commands and keyboard shortcuts for playback, the queue/lyrics
//  inspector, and sidebar navigation. Driven directly by the app-level
//  `PlayerState` and `Navigator` (passed in from the App scene), since commands
//  live outside the view hierarchy's environment.
//

import SwiftUI

struct MediaCommands: Commands {
    let player: PlayerState
    let navigator: Navigator
    @Environment(\.openWindow) private var openWindow

    private var nothingPlaying: Bool { player.nowPlaying == nil }

    var body: some Commands {
        // MARK: Controls
        CommandMenu("menu.controls") {
            Button(player.isPlaying ? String(localized: "menu.controls.pause") : String(localized: "common.play")) {
                player.togglePlayPause()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(nothingPlaying)

            Button("menu.controls.next") { player.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!player.canGoNext)

            Button("menu.controls.previous") { player.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(nothingPlaying)

            if player.isEpisode {
                Button(String(format: String(localized: "menu.controls.skip_back"), Int(PlayerState.skipBackSeconds))) {
                    player.skip(by: -PlayerState.skipBackSeconds)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button(String(format: String(localized: "menu.controls.skip_forward"), Int(PlayerState.skipForwardSeconds))) {
                    player.skip(by: PlayerState.skipForwardSeconds)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            }

            Divider()

            Button("menu.controls.volume_up") { adjustVolume(by: 0.05) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("menu.controls.volume_down") { adjustVolume(by: -0.05) }
                .keyboardShortcut(.downArrow, modifiers: .command)

            Divider()

            Button("menu.controls.shuffle") { player.toggleShuffle() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(player.queue.isEmpty)

            Button("menu.controls.repeat") { player.cycleRepeatMode() }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("menu.controls.like") { player.toggleLike() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(nothingPlaying)

            Button("menu.controls.dislike") { player.toggleDislike() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(nothingPlaying)
        }

        // MARK: View (inspector panels)
        CommandGroup(after: .sidebar) {
            Divider()
            Button("menu.view.queue") { navigator.togglePanel(.queue) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button(player.isEpisode ? String(localized: "menu.view.details") : String(localized: "menu.view.lyrics")) {
                navigator.togglePanel(player.isEpisode ? .details : .lyrics)
            }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("menu.view.comments") { navigator.togglePanel(.comments) }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Button("menu.view.fullscreen_lyrics") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    navigator.showingImmersiveLyrics.toggle()
                }
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
            .disabled(nothingPlaying)
            Button("menu.view.stats") { openWindow(id: "stats") }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(nothingPlaying)
        }

        // MARK: Go (sidebar navigation)
        CommandMenu("menu.go") {
            ForEach(Array(ContentView.Section.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { navigator.section = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }

    private func adjustVolume(by delta: Double) {
        player.volume = min(max(player.volume + delta, 0), 1)
    }
}
