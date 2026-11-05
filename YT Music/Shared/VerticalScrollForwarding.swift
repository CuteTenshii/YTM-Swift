//
//  VerticalScrollForwarding.swift
//  YT Music
//
//  Forwards vertical wheel events from horizontal-only scroll views to the enclosing one.
//

import AppKit

enum VerticalScrollForwarding {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { forward(event) ? nil : event }
        }
    }

    private static func forward(_ event: NSEvent) -> Bool {
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
              let content = event.window?.contentView,
              let hit = content.hitTest(content.convert(event.locationInWindow, from: nil)),
              let inner = enclosingScrollView(of: hit), !scrollsVertically(inner),
              let outer = inner.superview.flatMap(enclosingScrollView(of:)) else { return false }
        outer.scrollWheel(with: event)
        return true
    }

    private static func enclosingScrollView(of view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView { return scrollView }
            current = candidate.superview
        }
        return nil
    }

    private static func scrollsVertically(_ scrollView: NSScrollView) -> Bool {
        guard let document = scrollView.documentView else { return false }
        return document.frame.height > scrollView.contentView.bounds.height + 1
    }
}
