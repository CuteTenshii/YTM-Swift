//
//  LibraryView.swift
//  YT Music
//
//  The Library tab: the signed-in user's library as wrapping grids, filtered
//  by the server's chips (each chip is its own paginated browse page).
//  Requires authentication; prompts to sign in otherwise.
//

import SwiftUI

struct LibraryView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(Navigator.self) private var navigator
    let model: LibraryViewModel
    /// The card being renamed (drives the rename alert), and its draft name.
    @State private var renaming: HomeItem?
    @State private var renameText = ""
    /// The card pending delete confirmation.
    @State private var deleting: HomeItem?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16, alignment: .top)]

    var body: some View {
        @Bindable var navigator = navigator

        NavigationStack(path: $navigator.libraryPath) {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                switch model.state {
                case .loading:
                    ProgressView("Loading Library…")
                        .controlSize(.large)
                        .tint(.primary)
                        .foregroundStyle(.primary)

                case .signedOut:
                    signedOutView

                case .loaded:
                    content

                case .failed(let message):
                    errorView(message)
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: EntityDestination.self) { destination in
                EntityView(destination: destination)
            }
        }
        .alert("Rename Playlist", isPresented: renamingBinding) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let item = renaming, let id = item.editablePlaylistId {
                    Task { await model.renamePlaylist(id, to: renameText, isSignedIn: auth.isSignedIn) }
                }
                renaming = nil
            }
        }
        .alert("Delete Playlist", isPresented: deletingBinding) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let item = deleting, let id = item.editablePlaylistId {
                    Task { await model.deletePlaylist(id, isSignedIn: auth.isSignedIn) }
                }
                deleting = nil
            }
        } message: {
            if let item = deleting {
                Text("“\(item.title)” will be permanently deleted.")
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            FilterChipRow(chips: model.chips, title: \.title, selection: model.selectedChip) { chip in
                Task { await model.select(chip) }
            }
            .padding(.top, 16)
            .padding(.bottom, 8)

            switch model.visibleState {
            case .loading, .signedOut:
                Spacer()
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Spacer()
            case .failed(let message):
                errorView(message)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let page) where page.isEmpty:
                emptyFilterView
            case .loaded(let page):
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(page.shelves) { shelf in
                            shelfSection(shelf, lastItemID: page.shelves.last?.items.last?.id)
                        }
                        if !page.tracks.isEmpty {
                            TrackListView(tracks: page.tracks, album: "", hasMore: page.continuation != nil) {
                                Task { await model.loadMoreVisible() }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
        }
    }

    private func shelfSection(_ shelf: HomeShelf, lastItemID: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(shelf.items) { item in
                    ItemCard(item: item) {
                        if item.editablePlaylistId != nil {
                            Button {
                                renameText = item.title
                                renaming = item
                            } label: {
                                Label("Rename…", systemImage: "pencil")
                            }
                            Divider()
                            Button(role: .destructive) {
                                deleting = item
                            } label: {
                                Label("Delete Playlist…", systemImage: "trash")
                            }
                        }
                    }
                    .onAppear {
                        if item.id == lastItemID { Task { await model.loadMoreVisible() } }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deletingBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var emptyFilterView: some View {
        VStack {
            Spacer()
            Text("Nothing here yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var signedOutView: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Your library lives here")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Sign in to see your playlists, albums, and saved music.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Sign in") { auth.isPresentingLogin = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding(40)
        .frame(maxWidth: 380)
    }

    private func errorView(_ text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await model.load(isSignedIn: auth.isSignedIn) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(40)
        .frame(maxWidth: 380)
    }
}

#Preview {
    LibraryView(model: LibraryViewModel())
        .environment(PlayerState())
        .environment(AuthStore())
        .frame(width: 900, height: 600)
}
