//
//  LyricsRendering.swift
//  YT Music
//
//  Shared synced-lyrics rendering for the side panel and the immersive view.
//

import SwiftUI

struct LyricsStyle {
    var font: Font
    var activeColor: Color
    var inactiveColor: Color
    var lineSpacing: CGFloat
    var padding: EdgeInsets
    var maxBlur: CGFloat
    var scrollAnchor: UnitPoint
    var activeScale: CGFloat

    static let panel = LyricsStyle(
        font: .title3.weight(.semibold),
        activeColor: .primary,
        inactiveColor: Color.secondary.opacity(0.5),
        lineSpacing: 6,
        padding: EdgeInsets(top: 16, leading: 16, bottom: 140, trailing: 16),
        maxBlur: 0,
        scrollAnchor: .center,
        activeScale: 1.0
    )

    static let immersive = LyricsStyle(
        font: .system(size: 30, weight: .bold, design: .rounded),
        activeColor: .white,
        inactiveColor: Color.white.opacity(0.4),
        lineSpacing: 18,
        padding: EdgeInsets(top: 64, leading: 44, bottom: 220, trailing: 44),
        maxBlur: 5,
        scrollAnchor: UnitPoint(x: 0.5, y: 0.4),
        activeScale: 1.04
    )
}

struct SyncedLyricsScroller: View {
    let player: PlayerState
    let lines: [LyricLine]
    var source: String?
    var style: LyricsStyle

    private var focus: LyricsFocus { LyricsFocus.resolve(lines, at: player.currentTime) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: style.lineSpacing) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        if case .interlude(let before, let progress) = focus, before == index {
                            InterludeIndicator(progress: progress, color: style.activeColor)
                                .id("interlude-\(index)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
                        }
                        LyricLineRow(line: line,
                                     now: player.currentTime,
                                     appearance: appearance(for: index),
                                     style: style)
                            .id("line-\(line.id)")
                            .contentShape(.rect)
                            .onTapGesture { player.seek(to: line.time) }
                    }
                    if let source {
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(style.inactiveColor)
                            .padding(.top, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(style.padding)
                .animation(.easeInOut(duration: 0.3), value: interludeShown)
            }
            .onAppear { scroll(proxy, animated: false) }
            .onChange(of: scrollTarget) { _, _ in scroll(proxy, animated: true) }
        }
    }

    private var interludeShown: Bool {
        if case .interlude = focus { true } else { false }
    }

    private var scrollTarget: String? {
        switch focus {
        case .line(let i):            "line-\(lines[i].id)"
        case .interlude(let before, _): "interlude-\(before)"
        case .none:                   nil
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let target = scrollTarget else { return }
        if animated {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) {
                proxy.scrollTo(target, anchor: style.scrollAnchor)
            }
        } else {
            proxy.scrollTo(target, anchor: style.scrollAnchor)
        }
    }

    private func appearance(for index: Int) -> LyricLineRow.Appearance {
        switch focus {
        case .line(let active):
            .init(isActive: index == active, distance: abs(index - active))
        case .interlude(let before, _):
            .init(isActive: false, distance: abs(index - before) + 1)
        case .none:
            .init(isActive: false, distance: index + 1)
        }
    }
}

struct LyricLineRow: View {
    struct Appearance: Equatable {
        var isActive: Bool
        var distance: Int
    }

    let line: LyricLine
    let now: Double
    let appearance: Appearance
    let style: LyricsStyle

    var body: some View {
        content
            .font(style.font)
            .opacity(opacity)
            .blur(radius: appearance.isActive ? 0 : blur)
            .scaleEffect(appearance.isActive ? style.activeScale : 1, anchor: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: appearance)
    }

    @ViewBuilder
    private var content: some View {
        if appearance.isActive, !line.words.isEmpty {
            FlowLayout {
                ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                    Text(word.text)
                        .foregroundStyle(style.activeColor)
                        .opacity(now >= word.time ? 1 : 0.35)
                        .animation(.easeOut(duration: 0.25), value: now >= word.time)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(appearance.isActive ? style.activeColor : style.inactiveColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var opacity: Double {
        appearance.isActive ? 1 : max(0.3, 0.85 - 0.12 * Double(appearance.distance))
    }

    private var blur: CGFloat {
        min(CGFloat(max(appearance.distance - 1, 0)) * 0.7, style.maxBlur)
    }
}

struct InterludeIndicator: View {
    let progress: Double
    var color: Color = .primary

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .opacity(fill(i) * 0.7 + 0.25)
                    .scaleEffect(0.8 + 0.3 * fill(i))
            }
        }
        .padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.25), value: progress)
    }

    private func fill(_ i: Int) -> Double {
        min(max(progress * 3 - Double(i), 0), 1)
    }
}

struct PlainLyricsView: View {
    let lyrics: Lyrics
    var foreground: Color = .primary
    var font: Font = .body
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        ScrollView {
            VStack(alignment: alignment, spacing: 16) {
                Text(lyrics.text)
                    .font(font)
                    .foregroundStyle(foreground)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .textSelection(.enabled)
                if let source = lyrics.source {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(foreground.opacity(0.6))
                }
            }
            .padding(16)
        }
    }

    private var frameAlignment: Alignment {
        alignment == .center ? .center : .leading
    }
}

struct FlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight; x = 0; rowHeight = 0
            }
            x += size.width
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight; x = bounds.minX; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}
