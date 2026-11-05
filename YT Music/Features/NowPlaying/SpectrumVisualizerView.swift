//
//  SpectrumVisualizerView.swift
//  YT Music
//
//  Bar spectrum visualizer for the immersive view.
//

import SwiftUI

struct SpectrumVisualizerView: View {
    let analyzer: SpectrumAnalyzer?
    var colors: [Color]

    private var palette: [Color] {
        colors.isEmpty
            ? [Color(red: 0.35, green: 0.8, blue: 1.0), Color(red: 0.65, green: 0.4, blue: 1.0)]
            : colors
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            // Polled outside the Canvas; capturing the sample and tick date makes SwiftUI redraw each frame.
            let bands = analyzer?.magnitudes() ?? []
            Canvas { context, size in
                _ = timeline.date
                draw(&context, size: size, bands: bands)
            }
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, bands: [Float]) {
        let n = bands.count
        guard n > 0, size.width > 0, size.height > 0 else { return }

        let spacing: CGFloat = size.width > 700 ? 6 : 3
        let barW = max(2, (size.width - spacing * CGFloat(n - 1)) / CGFloat(n))
        let radius = min(barW / 2, 6)
        let maxH = size.height

        for i in 0..<n {
            let level = CGFloat(min(max(bands[i], 0), 1))
            let h = max(barW * 0.5, level * maxH)
            let x = CGFloat(i) * (barW + spacing)
            let rect = CGRect(x: x, y: maxH - h, width: barW, height: h)
            let c = color(at: i, count: n)
            context.fill(
                Path(roundedRect: rect, cornerRadius: radius),
                with: .linearGradient(
                    Gradient(colors: [c.opacity(0.5), c]),
                    startPoint: CGPoint(x: 0, y: maxH - h),
                    endPoint: CGPoint(x: 0, y: maxH)
                )
            )
        }
    }

    private func color(at index: Int, count: Int) -> Color {
        let p = palette
        guard p.count > 1 else { return p.first ?? .white }
        let t = Double(index) / Double(max(count - 1, 1)) * Double(p.count - 1)
        return p[min(p.count - 1, Int(t.rounded()))]
    }
}
