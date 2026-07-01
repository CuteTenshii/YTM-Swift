//
//  AddToPlaylistSheet.swift
//  YT Music
//
//  The "Add to Playlist" picker, presented from the app shell. Lists the user's
//  own playlists (tap to add the pending track), creates a new playlist seeded
//  with the track, and doubles as a lightweight manager: each playlist can be
//  renamed or deleted via its context menu.
//

import SwiftUI

@MainActor
@Observable
final class AddToPlaylistModel {
    enum State {
        case loading
        case loaded([EditablePlaylist])
        case failed(String)
    }

    private(set) var state: State = .loading
    /// True while an add / create / rename / delete request is in flight.
    private(set) var busy = false
    /// The track being added, remembered so rename/delete can refresh the list.
    private var videoId: String?

    private let client: InnerTubeClient

    init(client: InnerTubeClient = .shared) {
        self.client = client
    }

    func load(videoId: String) async {
        self.videoId = videoId
        state = .loading
        do {
            state = .loaded(try await client.addToPlaylistOptions(videoId: videoId))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Reloads the current track's options after a mutation (rename/delete).
    private func reload() async {
        if let videoId { await load(videoId: videoId) }
    }

    /// Adds the track to an existing playlist. Returns whether it succeeded.
    func add(videoId: String, to playlist: EditablePlaylist) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            try await client.addToPlaylist(playlistId: playlist.id, videoIds: [videoId])
            return true
        } catch {
            return false
        }
    }

    /// Creates a new playlist seeded with the track. Returns whether it succeeded.
    func create(name: String, seeding videoId: String) async -> Bool {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            try await client.createPlaylist(title: title, videoIds: [videoId])
            return true
        } catch {
            return false
        }
    }

    func rename(_ playlist: EditablePlaylist, to name: String) async {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        try? await client.renamePlaylist(playlistId: playlist.id, title: title)
        await reload()
    }

    func delete(_ playlist: EditablePlaylist) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        try? await client.deletePlaylist(playlistId: playlist.id)
        await reload()
    }
}

struct AddToPlaylistSheet: View {
    let add: PlaylistCoordinator.PendingAdd
    let onFinish: () -> Void

    @State private var model = AddToPlaylistModel()
    @State private var newName = ""
    /// The playlist being renamed (drives the rename alert), and its draft name.
    @State private var renaming: EditablePlaylist?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            newPlaylistRow
            Divider()
            list
        }
        .frame(width: 420, height: 520)
        .task { await model.load(videoId: add.videoId) }
        .alert("Rename Playlist", isPresented: renamingBinding) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let playlist = renaming {
                    Task { await model.rename(playlist, to: renameText) }
                }
                renaming = nil
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add to Playlist").font(.headline)
                Text(add.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Done") { onFinish() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    /// Create-and-add a brand new playlist.
    private var newPlaylistRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.square")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
            TextField("New playlist name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createNew)
            Button("Create", action: createNew)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || model.busy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var list: some View {
        switch model.state {
        case .loading:
            centered { ProgressView() }
        case .failed(let message):
            centered {
                VStack(spacing: 12) {
                    Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Try Again") { Task { await model.load(videoId: add.videoId) } }
                }
                .padding(24)
            }
        case .loaded(let playlists):
            if playlists.isEmpty {
                centered {
                    Text("You don't have any playlists yet.\nCreate one above.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(playlists) { playlist in
                            playlistRow(playlist)
                            Divider().padding(.leading, 70)
                        }
                    }
                }
            }
        }
    }

    private func playlistRow(_ playlist: EditablePlaylist) -> some View {
        Button {
            Task {
                if await model.add(videoId: add.videoId, to: playlist) { onFinish() }
            }
        } label: {
            HStack(spacing: 12) {
                ArtworkView(url: playlist.thumbnailURL, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.title).lineLimit(1)
                    if !playlist.subtitle.isEmpty {
                        Text(playlist.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
        .contextMenu {
            Button {
                renameText = playlist.title
                renaming = playlist
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                Task { await model.delete(playlist) }
            } label: {
                Label("Delete Playlist", systemImage: "trash")
            }
        }
    }

    private func createNew() {
        let name = newName
        Task {
            if await model.create(name: name, seeding: add.videoId) { onFinish() }
        }
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }
}
