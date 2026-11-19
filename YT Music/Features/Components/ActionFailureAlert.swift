//
//  ActionFailureAlert.swift
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
    func actionFailureAlert(_ failure: Binding<ActionFailure?>) -> some View {
        alert(
            failure.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { failure.wrappedValue != nil },
                set: { if !$0 { failure.wrappedValue = nil } }
            ),
            presenting: failure.wrappedValue
        ) { _ in
        } message: { failure in
            Text(failure.message)
        }
    }
}
