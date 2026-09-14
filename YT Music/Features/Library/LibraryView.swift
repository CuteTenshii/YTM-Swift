//
//  LibraryView.swift
//  YT Music
//
//  The Library tab: the signed-in user's playlists/albums as wrapping grids.
//  Requires authentication; prompts to sign in otherwise.
//

import SwiftUI

struct LibraryView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(Navigator.self) private var navigator
    @State private var model = LibraryViewModel()
    @State private var filter: LibraryFilter = .all
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
                Color.black.ignoresSafeArea()

                switch model.state {
                case .loading:
                    ProgressView("Loading Library…")
                        .controlSize(.large)
                        .tint(.white)
                        .foregroundStyle(.white)

                case .signedOut:
                    signedOutView

                case .loaded(let shelves):
                    content(shelves)

                case .failed(let message):
                    errorView(message)
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: EntityDestination.self) { destination in
                EntityView(destination: destination)
            }
        }
        .task(id: auth.generation) { await model.load(isSignedIn: auth.isSignedIn) }
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

    private func content(_ shelves: [HomeShelf]) -> some View {
        let available = LibraryFilter.available(for: shelves)
        let filtered = filter.apply(to: shelves)

        return VStack(alignment: .leading, spacing: 0) {
            FilterChips(filters: available, selection: $filter)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if filtered.isEmpty {
                emptyFilterView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(filtered) { shelf in
                            shelfSection(shelf)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
        }
    }

    private func shelfSection(_ shelf: HomeShelf) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
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
                .foregroundStyle(.white)
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
    LibraryView()
        .environment(PlayerState())
        .environment(AuthStore())
        .frame(width: 900, height: 600)
}

/// Horizontal row of selectable filter chips (YT Music style).
private struct FilterChips: View {
    let filters: [LibraryFilter]
    @Binding var selection: LibraryFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters) { filter in
                    let isSelected = filter == selection
                    Button {
                        selection = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isSelected ? Color.white : Color.white.opacity(0.12))
                            .foregroundStyle(isSelected ? Color.black : Color.white)
                            .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
    }
}
