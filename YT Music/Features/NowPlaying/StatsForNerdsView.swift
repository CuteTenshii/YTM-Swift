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
            ("Video ID", track?.videoId ?? "—"),
            ("Source client", details?.source ?? "—"),
            ("Format (itag)", details?.itag.map(String.init) ?? "—"),
            ("MIME type", details?.mimeType ?? "—"),
            ("Bitrate", details?.bitrate.map { "\($0 / 1000) kbps" } ?? "—"),
            ("Audio quality", details?.audioQuality ?? "—"),
            ("Stream host", details?.host ?? "—"),
            ("Position", "\(Self.time(player.currentTime)) / \(Self.time(player.duration))"),
            ("Buffered ahead", String(format: "%.1f s", ahead)),
            ("State", player.isBuffering ? "Buffering" : player.isPlaying ? "Playing" : "Paused"),
            ("Speed", String(format: "%.2fx", player.playbackRate)),
            ("Volume", "\(Int(player.volume * 100))%"),
        ]
    }

    private static func time(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
