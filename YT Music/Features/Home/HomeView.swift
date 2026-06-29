//
//  HomeView.swift
//  YT Music
//
//  The Home tab: a vertical stack of horizontally-scrolling shelves, rendered
//  from the live YouTube Music `FEmusic_home` feed. Owns the navigation stack
//  that pushes album/playlist/artist pages.
//

import SwiftUI

struct HomeView: View {
    @Environment(AuthStore.self) private var auth
    @State private var model = HomeViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch model.state {
                case .idle, .loading:
                    ProgressView("Loading Home…")
                        .controlSize(.large)
                        .tint(.white)
                        .foregroundStyle(.white)

                case .loaded(let feed):
                    feedContent(feed)

                case .failed(let message):
                    errorView(message)
                }
            }
            .navigationTitle("Home")
            .navigationDestination(for: EntityDestination.self) { destination in
                EntityView(destination: destination)
            }
        }
        .task(id: auth.generation) { await model.load() }
    }

    // MARK: - Feed

    private func feedContent(_ feed: HomeFeed) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                ForEach(feed.shelves) { shelf in
                    ShelfView(shelf: shelf)
                }
            }
            .padding(.vertical, 24)
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Couldn't load Home")
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
    HomeView()
        .environment(PlayerState())
        .environment(AuthStore())
        .frame(width: 900, height: 600)
}
