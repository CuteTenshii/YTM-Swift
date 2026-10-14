//
//  SponsorBlockPlugin.swift
//  YT Music
//
//  Skips community-submitted SponsorBlock segments (non-music sections,
//  sponsors, intros, ...) in the playing track. The configuration UI picks
//  which categories are skipped.
//

import SwiftUI

@MainActor
@Observable
final class SponsorBlockPlugin: Plugin {
    let id = "sponsorblock"
    let name = "SponsorBlock"
    let summary = "Skip non-music sections, sponsors, and intros in music videos, using the community SponsorBlock database."

    var categories: Set<SponsorBlockCategory> {
        didSet {
            defaults.set(categories.map(\.rawValue), forKey: Self.categoriesKey)
            if let videoId { load(videoId) }
        }
    }

    private let client = SponsorBlockClient()
    private let defaults: UserDefaults
    private weak var player: PlayerState?
    private var active = false
    private var videoId: String?
    private var segments: [SponsorSegment] = []
    private var skipped: Set<String> = []
    private var fetchTask: Task<Void, Never>?

    private static let categoriesKey = "plugins.sponsorblock.categories"

    init(player: PlayerState?, defaults: UserDefaults = .standard) {
        self.player = player
        self.defaults = defaults
        self.categories = defaults.stringArray(forKey: Self.categoriesKey)
            .map { Set($0.compactMap(SponsorBlockCategory.init)) } ?? SponsorBlockCategory.defaults
    }

    func setActive(_ active: Bool) {
        self.active = active
        if active {
            playbackDidChange(player?.currentSnapshot)
        } else {
            reset()
        }
    }

    func playbackDidChange(_ snapshot: PlaybackSnapshot?) {
        guard active else { return }
        guard let snapshot else {
            reset()
            return
        }
        if snapshot.videoId != videoId {
            reset()
            videoId = snapshot.videoId
            load(snapshot.videoId)
        } else if let player, player.isLoading || player.crossfadeLoading {
            // Same track started again: its segments apply afresh.
            skipped = []
        }
    }

    func playbackDidProgress(currentTime: Double, duration: Double) {
        // Until the new track's audio takes over, ticks come from the previous track.
        guard active, let player, !player.isLoading, !player.crossfadeLoading,
              let segment = SponsorBlockAPI.segmentToSkip(at: currentTime, in: segments, skipped: skipped)
        else { return }
        skipped.insert(segment.id)
        player.seek(to: segment.end)
    }

    private func load(_ videoId: String) {
        fetchTask?.cancel()
        segments = []
        skipped = []
        let categories = categories
        fetchTask = Task {
            let found = (try? await client.segments(videoId: videoId, categories: categories)) ?? []
            guard !Task.isCancelled, self.videoId == videoId else { return }
            segments = found
        }
    }

    private func reset() {
        fetchTask?.cancel()
        fetchTask = nil
        videoId = nil
        segments = []
        skipped = []
    }

    var configuration: AnyView? { AnyView(SponsorBlockConfigView(plugin: self)) }
}

/// Per-category skip toggles shown under the plugin toggle.
private struct SponsorBlockConfigView: View {
    @Bindable var plugin: SponsorBlockPlugin

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Skip these segments")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(SponsorBlockCategory.allCases) { category in
                Toggle(category.label, isOn: Binding(
                    get: { plugin.categories.contains(category) },
                    set: { isOn in
                        if isOn { plugin.categories.insert(category) } else { plugin.categories.remove(category) }
                    }
                ))
            }
        }
    }
}
