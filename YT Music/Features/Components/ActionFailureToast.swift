//
//  ActionFailureToast.swift
//  YT Music
//

import SwiftUI

struct ActionFailure: Equatable {
    let title: String
    let message: String

    init(title: String, error: Error) {
        self.title = title
        self.message = error.localizedDescription
    }
}

extension View {
    /// Shows each failure as an error toast, then clears it.
    func actionFailureToast(_ failure: Binding<ActionFailure?>) -> some View {
        modifier(ActionFailureToast(failure: failure))
    }
}

private struct ActionFailureToast: ViewModifier {
    @Binding var failure: ActionFailure?
    @Environment(ToastCenter.self) private var toasts

    func body(content: Content) -> some View {
        content.onChange(of: failure) { _, failure in
            guard let failure else { return }
            toasts.show(Toast(title: failure.title, message: failure.message, style: .error))
            self.failure = nil
        }
    }
}
