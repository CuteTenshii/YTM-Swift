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
    @State private var renaming: ShelfItem?
    @State private var renameText = ""
    @State private var deleting: ShelfItem?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16, alignment: .top)]

    var body: some View {
        @Bindable var navigator = navigator

        NavigationStack(path: $navigator.libraryPath) {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                switch model.state {
                case .loading:
                    ProgressView("library.loading")
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
            .pageTitle(String(localized: "library.title"))
            .navigationDestination(for: EntityDestination.self) { destination in
                EntityView(destination: destination)
            }
        }
        .alert("playlists.add.rename.title", isPresented: renamingBinding) {
            TextField("playlists.field.name", text: $renameText)
            Button("common.cancel", role: .cancel) { renaming = nil }
            Button("playlists.rename") {
                if let item = renaming, let id = item.editablePlaylistId {
                    Task { await model.renamePlaylist(id, to: renameText, isSignedIn: auth.isSignedIn) }
                }
                renaming = nil
            }
        }
        .alert("playlists.delete", isPresented: deletingBinding) {
            Button("common.cancel", role: .cancel) { deleting = nil }
            Button("common.delete", role: .destructive) {
                if let item = deleting, let id = item.editablePlaylistId {
                    Task { await model.deletePlaylist(id, isSignedIn: auth.isSignedIn) }
                }
                deleting = nil
            }
        } message: {
            if let item = deleting {
                Text(String(format: String(localized: "entity.delete.message"), item.title))
            }
        }
    }

    private var chipRow: some View {
        FilterChipRow(chips: model.chips, title: \.title, selection: model.selectedChip) { chip in
            Task { await model.select(chip) }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.visibleState {
            case .loading, .signedOut:
                chipRow
                Spacer()
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Spacer()
            case .failed(let message):
                chipRow
                errorView(message)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let page) where page.isEmpty:
                chipRow
                emptyFilterView
            case .loaded(let page):
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        chipRow
                        LazyVStack(alignment: .leading, spacing: 28) {
                            ForEach(page.shelves) { shelf in
                                shelfSection(shelf, showsTitle: page.shelves.count > 1, lastItemID: page.shelves.last?.items.last?.id)
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
    }

    private func shelfSection(_ shelf: Shelf, showsTitle: Bool, lastItemID: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle {
                Text(shelf.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(shelf.items) { item in
                    ItemCard(item: item) {
                        if item.editablePlaylistId != nil {
                            Button {
                                renameText = item.title
                                renaming = item
                            } label: {
                                Label("playlists.rename.menu", systemImage: "pencil")
                            }
                            Divider()
                            Button(role: .destructive) {
                                deleting = item
                            } label: {
                                Label("playlists.delete.menu", systemImage: "trash")
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
            Text("library.empty.filter")
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
            Text("library.signed_out.title")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text("library.signed_out.message")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("common.sign_in") { auth.isPresentingLogin = true }
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
            Button("common.retry") {
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
        .environment(AppSettings())
        .frame(width: 900, height: 600)
}
