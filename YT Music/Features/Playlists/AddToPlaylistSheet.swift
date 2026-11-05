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
    private(set) var busy = false
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

    private func reload() async {
        if let videoId { await load(videoId: videoId) }
    }

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
        .alert("playlists.add.rename.title", isPresented: renamingBinding) {
            TextField("playlists.field.name", text: $renameText)
            Button("common.cancel", role: .cancel) { renaming = nil }
            Button("playlists.rename") {
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
                Text("playlists.add.title").font(.headline)
                Text(add.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("common.done") { onFinish() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var newPlaylistRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.square")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
            TextField("playlists.add.new_name.placeholder", text: $newName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createNew)
            Button("playlists.add.create", action: createNew)
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
                    Button("common.retry") { Task { await model.load(videoId: add.videoId) } }
                }
                .padding(24)
            }
        case .loaded(let playlists):
            if playlists.isEmpty {
                centered {
                    Text("playlists.add.empty")
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
                Label("playlists.rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                Task { await model.delete(playlist) }
            } label: {
                Label("playlists.delete", systemImage: "trash")
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
