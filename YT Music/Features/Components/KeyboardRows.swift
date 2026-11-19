//
//  KeyboardRows.swift
//  YT Music
//

import SwiftUI

extension View {
    /// Lets a row take keyboard focus and play with Return, and exposes it to VoiceOver as a button.
    func playableRow(_ play: @escaping () -> Void) -> some View {
        focusable(interactions: .edit)
            .onKeyPress(.return) {
                play()
                return .handled
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { play() }
    }

    /// Moves row focus with the up and down arrows, scrolling the target into view.
    func rowArrowNavigation<ID: Hashable>(_ focus: FocusState<ID?>.Binding, ids: [ID],
                                          proxy: ScrollViewProxy) -> some View {
        onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard let current = focus.wrappedValue, let index = ids.firstIndex(of: current) else { return .ignored }
            let step = press.key == .downArrow ? 1 : -1
            let target = ids[min(max(index + step, 0), ids.count - 1)]
            proxy.scrollTo(target)
            Task { focus.wrappedValue = target }
            return .handled
        }
    }
}
