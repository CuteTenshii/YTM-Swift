//
//  EditPlaylistSheet.swift
//  YT Music
//
//  The metadata editor for one of the user's own playlists, name, visibility,
//  description, presented from the playlist page. It edits the values the
//  page already loaded, so there's no extra fetch: the picker shows the
//  playlist's actual visibility as parsed from the page header (Private, the
//  visibility playlists are created with, when the header didn't say), and
//  saving sends only the fields that changed, a visibility the page never
//  reported is never sent unless you pick one.
//

import SwiftUI

struct EditPlaylistSheet: View {
    private let save: (_ name: String, _ description: String, _ privacy: PlaylistPrivacy?,
                       _ votePermission: Int?) async -> Bool
    private let voteOptions: [PlaylistVoteOption]
    private let onFinish: () -> Void

    @State private var name: String
    @State private var description: String
    @State private var privacy: PlaylistPrivacy?
    @State private var votePermission: Int?
    @State private var isSaving = false
    @State private var failed = false

    init(name: String,
         description: String,
         privacy: PlaylistPrivacy?,
         voteOptions: [PlaylistVoteOption],
         save: @escaping (_ name: String, _ description: String, _ privacy: PlaylistPrivacy?,
                          _ votePermission: Int?) async -> Bool,
         onFinish: @escaping () -> Void) {
        _name = State(initialValue: name)
        _description = State(initialValue: description)
        _privacy = State(initialValue: privacy)
        _votePermission = State(initialValue: voteOptions.first(where: \.isSelected)?.value)
        self.voteOptions = voteOptions
        self.save = save
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("playlists.edit.title").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("playlists.field.name")
                TextField("playlists.field.name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("playlists.edit.visibility")
                DescribedMenu(
                    selection: displayedPrivacy,
                    choices: PlaylistPrivacy.allCases.map {
                        .init(value: $0, title: visibilityLabel($0), detail: visibilityDetail($0))
                    }
                )
            }

            if !voteOptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("playlists.edit.voting")
                    DescribedMenu(
                        selection: $votePermission,
                        choices: voteOptions.map {
                            .init(value: Optional($0.value), title: $0.title, detail: $0.detail,
                                  isDisabled: $0.isDisabled)
                        }
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("playlists.edit.description")
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
                        Text("playlists.edit.description.placeholder")
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
                    Text("playlists.edit.save_failed")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 0)
                Button("common.cancel") { onFinish() }
                    .keyboardShortcut(.cancelAction)
                Button("common.save") { saveEdits() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(16)
        .frame(width: 460, height: voteOptions.isEmpty ? 380 : 440)
    }

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var displayedPrivacy: Binding<PlaylistPrivacy> {
        Binding(
            get: { privacy ?? .private },
            set: { privacy = $0 }
        )
    }

    private func visibilityLabel(_ level: PlaylistPrivacy) -> String {
        switch level {
        case .private: return String(localized: "playlists.visibility.private")
        case .unlisted: return String(localized: "playlists.visibility.unlisted")
        case .public: return String(localized: "playlists.visibility.public")
        }
    }

    private func visibilityDetail(_ level: PlaylistPrivacy) -> String {
        switch level {
        case .private: return String(localized: "playlists.visibility.private.detail")
        case .unlisted: return String(localized: "playlists.visibility.unlisted.detail")
        case .public: return String(localized: "playlists.visibility.public.detail")
        }
    }

    private func saveEdits() {
        guard !isSaving else { return }
        isSaving = true
        failed = false
        Task {
            let applied = await save(name, description, privacy, votePermission)
            isSaving = false
            if applied {
                onFinish()
            } else {
                failed = true
            }
        }
    }
}
