//
//  VerticalScrollForwarding.swift
//  YT Music
//
//  A horizontal-only scroll view swallows vertical wheel events, so the page
//  behind it stops scrolling while the pointer is over a shelf. This monitor
//  hands those events to the next scroll view up the hierarchy.
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

    /// True when the event was handed to an outer scroll view.
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
