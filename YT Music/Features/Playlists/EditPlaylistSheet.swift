//
//  EditPlaylistSheet.swift
//  YT Music
//
//  The metadata editor for one of the user's own playlists — name, visibility,
//  description — presented from the playlist page. It edits the values the
//  page already loaded, so there's no extra fetch: the picker shows the
//  playlist's actual visibility as parsed from the page header (Private, the
//  visibility playlists are created with, when the header didn't say), and
//  saving sends only the fields that changed — a visibility the page never
//  reported is never sent unless you pick one.
//

import SwiftUI

struct EditPlaylistSheet: View {
    /// Applies the edits; returns whether they were applied.
    private let save: (_ name: String, _ description: String, _ privacy: PlaylistPrivacy?) async -> Bool
    /// Dismisses the sheet (called on cancel or after a successful save).
    private let onFinish: () -> Void

    @State private var name: String
    @State private var description: String
    @State private var privacy: PlaylistPrivacy?
    @State private var isSaving = false
    @State private var failed = false

    init(name: String,
         description: String,
         privacy: PlaylistPrivacy?,
         save: @escaping (_ name: String, _ description: String, _ privacy: PlaylistPrivacy?) async -> Bool,
         onFinish: @escaping () -> Void) {
        _name = State(initialValue: name)
        _description = State(initialValue: description)
        _privacy = State(initialValue: privacy)
        self.save = save
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Playlist").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Name")
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Visibility")
                Picker("Visibility", selection: displayedPrivacy) {
                    ForEach(PlaylistPrivacy.allCases, id: \.self) { level in
                        Text(visibilityLabel(level)).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 220, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Description")
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $description)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(.rect(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.quaternary, lineWidth: 1)
                        )
                    if description.isEmpty {
                        Text("Add a description for this playlist")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 110)
            }

            HStack(spacing: 12) {
                if failed {
                    Text("Couldn't save. Check your connection and try again.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 0)
                Button("Cancel") { onFinish() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveEdits() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(16)
        .frame(width: 460, height: 380)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// The picker selection as displayed: the playlist's actual visibility
    /// when the page parsed one, and Private — the visibility playlists are
    /// created with — when it didn't. Picking updates `privacy`, which stays
    /// nil (and is therefore never sent) while untouched.
    private var displayedPrivacy: Binding<PlaylistPrivacy> {
        Binding(
            get: { privacy ?? .private },
            set: { privacy = $0 }
        )
    }

    private func visibilityLabel(_ level: PlaylistPrivacy) -> String {
        switch level {
        case .private: return "Private"
        case .unlisted: return "Unlisted"
        case .public: return "Public"
        }
    }

    private func saveEdits() {
        guard !isSaving else { return }
        isSaving = true
        failed = false
        Task {
            let applied = await save(name, description, privacy)
            isSaving = false
            if applied {
                onFinish()
            } else {
                failed = true
            }
        }
    }
}
