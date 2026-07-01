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

    private var nothingPlaying: Bool { player.nowPlaying == nil }

    var body: some Commands {
        // MARK: Controls
        CommandMenu("Controls") {
            Button(player.isPlaying ? "Pause" : "Play") {
                player.togglePlayPause()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(nothingPlaying)

            Button("Next Track") { player.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!player.canGoNext)

            Button("Previous Track") { player.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(nothingPlaying)

            Divider()

            Button("Volume Up") { adjustVolume(by: 0.05) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Volume Down") { adjustVolume(by: -0.05) }
                .keyboardShortcut(.downArrow, modifiers: .command)

            Divider()

            Button("Toggle Shuffle") { player.toggleShuffle() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(player.queue.isEmpty)

            Button("Cycle Repeat Mode") { player.cycleRepeatMode() }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Like Song") { player.toggleLike() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(nothingPlaying)
        }

        // MARK: View (inspector panels)
        CommandGroup(after: .sidebar) {
            Divider()
            Button("Show Queue") { navigator.togglePanel(.queue) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Show Lyrics") { navigator.togglePanel(.lyrics) }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("Show Comments") { navigator.togglePanel(.comments) }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Button("Full-Screen Lyrics") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    navigator.showingImmersiveLyrics.toggle()
                }
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
            .disabled(nothingPlaying)
        }

        // MARK: Go (sidebar navigation)
        CommandMenu("Go") {
            ForEach(Array(ContentView.Section.allCases.enumerated()), id: \.element) { index, section in
                Button(section.rawValue) { navigator.section = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }

    private func adjustVolume(by delta: Double) {
        player.volume = min(max(player.volume + delta, 0), 1)
    }
}
