//
//  ToastCenter.swift
//  YT Music
//

import SwiftUI

struct Toast: Identifiable {
    enum Style {
        case info
        case error
    }

    struct Action {
        let title: String
        let perform: () -> Void
    }

    let id = UUID()
    var title: String?
    let message: String
    var style: Style = .info
    var action: Action?
}

/// App-wide transient messages; the newest toast replaces the one on screen.
@Observable
final class ToastCenter {
    static let defaultDuration: Duration = .seconds(5)

    private(set) var current: Toast?
    private var duration = defaultDuration
    private var dismissTask: Task<Void, Never>?

    func show(_ toast: Toast, for duration: Duration = defaultDuration) {
        current = toast
        self.duration = duration
        AccessibilityNotification.Announcement([toast.title, toast.message].compactMap { $0 }.joined(separator: ". ")).post()
        scheduleDismissal()
    }

    /// Dismisses the toast on screen, or only the given one when `id` is set.
    func dismiss(_ id: Toast.ID? = nil) {
        guard let current, id == nil || id == current.id else { return }
        dismissTask?.cancel()
        self.current = nil
    }

    /// Keeps the toast up while the pointer is over it.
    func setHovering(_ hovering: Bool) {
        if hovering {
            dismissTask?.cancel()
        } else {
            scheduleDismissal()
        }
    }

    private func scheduleDismissal() {
        dismissTask?.cancel()
        guard let id = current?.id else { return }
        let duration = duration
        dismissTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            dismiss(id)
        }
    }
}
