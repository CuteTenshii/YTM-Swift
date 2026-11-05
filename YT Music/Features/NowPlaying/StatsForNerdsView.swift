//
//  StatsForNerdsView.swift
//  YT Music
//

import SwiftUI

struct StatsForNerdsView: View {
    let player: PlayerState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Form {
                ForEach(rows, id: \.0) { label, value in
                    LabeledContent(label) {
                        Text(value).textSelection(.enabled).monospacedDigit()
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 420)
        .frame(minHeight: 240, idealHeight: 440, maxHeight: .infinity)
    }

    private var rows: [(String, String)] {
        let track = player.nowPlaying
        let details = player.streamDetails?.videoId == track?.videoId ? player.streamDetails : nil
        let ahead = max(player.bufferedTime - player.currentTime, 0)
        return [
            (String(localized: "nowplaying.stats.video_id"), track?.videoId ?? "-"),
            (String(localized: "nowplaying.stats.source"), details?.source ?? "-"),
            (String(localized: "nowplaying.stats.format"), details?.itag.map(String.init) ?? "-"),
            (String(localized: "nowplaying.stats.mime"), details?.mimeType ?? "-"),
            (String(localized: "nowplaying.stats.bitrate"), details?.bitrate.map { "\($0 / 1000) kbps" } ?? "-"),
            (String(localized: "nowplaying.stats.quality"), details?.audioQuality ?? "-"),
            (String(localized: "nowplaying.stats.host"), details?.host ?? "-"),
            (String(localized: "nowplaying.stats.position"), "\(Self.time(player.currentTime)) / \(Self.time(player.duration))"),
            (String(localized: "nowplaying.stats.buffered"), String(format: "%.1f s", ahead)),
            (String(localized: "nowplaying.stats.state"), stateText),
            (String(localized: "nowplaying.stats.speed"), String(format: "%.2fx", player.playbackRate)),
            (String(localized: "nowplaying.stats.volume"), "\(Int(player.volume * 100))%"),
        ]
    }

    private var stateText: String {
        if player.isBuffering { return String(localized: "nowplaying.stats.state.buffering") }
        return player.isPlaying ? String(localized: "nowplaying.stats.state.playing") : String(localized: "nowplaying.stats.state.paused")
    }

    private static func time(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
