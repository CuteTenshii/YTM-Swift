//
//  ExploreView.swift
//  YT Music
//
//  The Explore tab: YouTube Music's `FEmusic_explore` landing — new releases,
//  charts, and trending — as a vertical stack of horizontal shelves. Mirrors
//  Home, and works signed out. Its stack binds to the Navigator's `explorePath`.
//

import SwiftUI

struct ExploreView: View {
    @Environment(Navigator.self) private var navigator
    @State private var model = ExploreViewModel()

    var body: some View {
        @Bindable var navigator = navigator

        NavigationStack(path: $navigator.explorePath) {
            ZStack {
                Color.black.ignoresSafeArea()

                switch model.state {
                case .idle, .loading:
                    ProgressView("Loading Explore…")
                        .controlSize(.large)
                        .tint(.white)
                        .foregroundStyle(.white)

                case .loaded(let shelves):
                    content(shelves)

                case .failed(let message):
                    errorView(message)
                }
            }
            .navigationTitle("Explore")
            .navigationDestination(for: EntityDestination.self) { destination in
                EntityView(destination: destination)
            }
        }
        .task { await model.loadIfNeeded() }
    }

    private func content(_ shelves: [HomeShelf]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                ForEach(shelves) { shelf in
                    ShelfView(shelf: shelf)
                }
            }
            .padding(.vertical, 24)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Couldn't load Explore")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await model.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(40)
        .frame(maxWidth: 380)
    }
}

#Preview {
    ExploreView()
        .environment(PlayerState())
        .environment(AuthStore())
        .environment(Navigator())
        .frame(width: 900, height: 600)
}
