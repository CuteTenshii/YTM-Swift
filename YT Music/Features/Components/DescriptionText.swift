import AppKit
import SwiftUI

nonisolated enum DescriptionLinker {
    private static let mention = /@[A-Za-z0-9_][A-Za-z0-9._-]*[A-Za-z0-9_]/

    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let full = NSRange(text.startIndex..., in: text)
        for match in detector?.matches(in: text, range: full) ?? [] {
            guard let url = match.url, let range = Range(match.range, in: text),
                  let target = Range(range, in: result) else { continue }
            result[target].link = url
        }
        for match in text.matches(of: mention) {
            let before = text[..<match.range.lowerBound].last
            guard before.map({ !$0.isLetter && !$0.isNumber && $0 != "@" }) ?? true,
                  let target = Range(match.range, in: result),
                  result[target].link == nil,
                  let url = URL(string: "https://www.youtube.com/\(text[match.range])") else { continue }
            result[target].link = url
        }
        return result
    }
}

/// A description clamped to a few lines with a More/Less toggle when it overflows.
/// Expanded text scrolls past `maxExpandedHeight` so it can't push its header off-screen.
struct DescriptionText: View {
    let text: String
    var style: AnyShapeStyle = AnyShapeStyle(.secondary)
    var lineLimit = 3
    var maxExpandedHeight: CGFloat = 160

    @Environment(Navigator.self) private var navigator
    @Environment(PlayerState.self) private var player
    @State private var expanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var clampedHeight: CGFloat = 0

    private var isTruncated: Bool { fullHeight > clampedHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if expanded {
                ScrollView { label.fixedSize(horizontal: false, vertical: true) }
                    .frame(height: min(fullHeight, maxExpandedHeight))
            } else {
                label.lineLimit(lineLimit)
            }
            if isTruncated || expanded {
                Button(expanded ? "Less" : "More") { expanded.toggle() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .background(alignment: .topLeading) {
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { fullHeight = $0 })
        }
        .environment(\.openURL, OpenURLAction { url in
            switch MusicLinks.target(for: url) {
            case .entity(let link):
                navigator.open(link.destination)
            case .watch(let videoId, let playlistId):
                player.playAll(videoId: videoId, playlistId: playlistId ?? MixIds.songRadio(for: videoId))
            case .handle(let handle):
                Task {
                    if let link = try? await InnerTubeClient.shared.resolveHandle(handle) {
                        navigator.open(link.destination)
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                }
            case nil:
                return .systemAction
            }
            return .handled
        })
    }

    private var label: some View {
        Text(DescriptionLinker.attributed(text))
            .font(.caption)
            .foregroundStyle(style)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { clampedHeight = $0 })
    }
}
