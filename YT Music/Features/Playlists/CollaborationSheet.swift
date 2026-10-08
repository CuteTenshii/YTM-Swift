//
//  CollaborationSheet.swift
//  YT Music
//

import SwiftUI

struct CollaborationSheet: View {
    let playlistId: String
    let title: String
    /// Re-read on open: the loaded page may predate a visibility change.
    let destination: EntityDestination
    let onFinish: () -> Void

    private enum Setting {
        case collaborate
        case allowNewCollaborators
    }

    private enum LoadState {
        case loading
        case failed
        /// Private playlists can't be collaborative.
        case unavailable
        case loaded(PlaylistCollaboration)
    }

    @Environment(Navigator.self) private var navigator

    @State private var state = LoadState.loading
    @State private var panel: CollaborationPanelRef?
    /// The switch whose change is in flight, shown flipped to its new value.
    @State private var pending: (setting: Setting, value: Bool)?
    @State private var updateFailed = false
    @State private var confirmingTurnOff = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 420, height: 480)
        .task { await load() }
        .alert("Turn off collaboration?", isPresented: $confirmingTurnOff) {
            Button("Cancel", role: .cancel) {}
            Button("Turn Off", role: .destructive) {
                Task {
                    await update(.collaborate, to: false) { try await $0.setCollaborationEnabled(playlistId: playlistId, false) }
                }
            }
        } message: {
            Text("Collaborators will be removed from the playlist. Tracks they added will stay.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Collaborate").font(.headline)
                Text(title)
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

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            centered { ProgressView() }
        case .failed:
            centered {
                VStack(spacing: 12) {
                    Text("Couldn't load collaboration settings.").foregroundStyle(.secondary)
                    Button("Try Again") { Task { await load() } }
                }
            }
        case .unavailable:
            centered {
                Text("Private playlists can't be collaborative.\nMake this playlist public or unlisted in Edit Playlist first.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(24)
            }
        case .loaded(let collaboration):
            settings(collaboration)
        }
    }

    private func settings(_ collaboration: PlaylistCollaboration) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: Binding(
                    get: { value(of: .collaborate, current: collaboration.isEnabled) },
                    set: { on in
                        if on {
                            Task {
                                await update(.collaborate, to: true) { try await $0.setCollaborationEnabled(playlistId: playlistId, true) }
                            }
                        } else {
                            confirmingTurnOff = true
                        }
                    }
                )) {
                    labelled("Collaborate", "Collaborators can add tracks", setting: .collaborate)
                }

                if collaboration.isEnabled {
                    Toggle(isOn: Binding(
                        get: { value(of: .allowNewCollaborators, current: collaboration.allowsNewCollaborators) },
                        set: { allowed in
                            Task {
                                await update(.allowNewCollaborators, to: allowed) {
                                    try await $0.setAllowsNewCollaborators(playlistId: playlistId, allowed)
                                }
                            }
                        }
                    )) {
                        labelled("Allow new collaborators", "Turn off to stop new people from joining",
                                 setting: .allowNewCollaborators)
                    }

                    if let invite = collaboration.inviteURL {
                        HStack {
                            Button {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(invite.absoluteString, forType: .string)
                            } label: {
                                Label("Copy Invite Link", systemImage: "link")
                            }
                            ShareLink(item: invite)
                        }
                    }
                }

                if updateFailed {
                    Text("Couldn't update collaboration. Check your connection and try again.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if !collaboration.collaborators.isEmpty {
                    Divider()
                    Text("Collaborators").font(.caption).foregroundStyle(.secondary)
                    ForEach(collaboration.collaborators, id: \.self) { collaborator in
                        if let link = collaborator.link {
                            Button {
                                onFinish()
                                navigator.open(link.destination)
                            } label: {
                                collaboratorRow(collaborator).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        } else {
                            collaboratorRow(collaborator)
                        }
                    }
                }
            }
            .toggleStyle(.switch)
            .disabled(pending != nil)
            .padding(16)
        }
    }

    private func collaboratorRow(_ collaborator: PlaylistCollaborator) -> some View {
        HStack(spacing: 10) {
            ArtworkView(url: collaborator.avatarURL, circular: true, size: 32)
            Text(collaborator.name)
            Spacer(minLength: 0)
            if !collaborator.role.isEmpty {
                Text(collaborator.role).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func labelled(_ title: String, _ subtitle: String, setting: Setting) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if pending?.setting == setting {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func value(of setting: Setting, current: Bool) -> Bool {
        if let pending, pending.setting == setting { return pending.value }
        return current
    }

    private func load() async {
        do {
            if panel == nil {
                panel = try await InnerTubeClient.shared.entity(destination).header.collaborationPanel
            }
            guard let panel else {
                state = .unavailable
                return
            }
            state = .loaded(try await InnerTubeClient.shared.collaboration(panel: panel))
        } catch {
            state = .failed
        }
    }

    /// Runs an edit, then reloads so the toggles and invite link show the server's state.
    private func update(_ setting: Setting, to value: Bool, _ edit: (InnerTubeClient) async throws -> Void) async {
        pending = (setting, value)
        updateFailed = false
        defer { pending = nil }
        do {
            try await edit(.shared)
            await load()
        } catch {
            updateFailed = true
        }
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
