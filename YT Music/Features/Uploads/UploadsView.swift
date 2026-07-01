//
//  UploadsView.swift
//  YT Music
//
//  The Uploads tab: music the signed-in user has uploaded to YT Music, shown as
//  wrapping grids like the Library, plus a toolbar action to upload a local
//  audio file. Requires authentication; prompts to sign in otherwise.
//

import SwiftUI
import UniformTypeIdentifiers

struct UploadsView: View {
    @Environment(AuthStore.self) private var auth
    @State private var model = UploadsViewModel()
    @State private var showingImporter = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16, alignment: .top)]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch model.state {
                case .loading:
                    ProgressView("Loading Uploads…")
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
            .navigationTitle("Uploads")
            .toolbar {
                if auth.isSignedIn {
                    ToolbarItem {
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Upload music", systemImage: "square.and.arrow.up")
                        }
                        .disabled(model.isUploading)
                        .help("Upload an audio file to your library")
                    }
                }
            }
            .navigationDestination(for: EntityDestination.self) { destination in
                EntityView(destination: destination)
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                upload(url)
            }
        }
        .task(id: auth.generation) { await model.load(isSignedIn: auth.isSignedIn) }
    }

    /// Uploads a picked file, keeping its security-scoped access open for the
    /// duration of the transfer.
    private func upload(_ url: URL) {
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            await model.upload(fileURL: url, isSignedIn: auth.isSignedIn)
        }
    }

    @ViewBuilder
    private func content(_ shelves: [HomeShelf]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            uploadBanner

            if shelves.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(shelves) { shelf in
                            shelfSection(shelf)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
        }
    }

    /// A slim banner reflecting an in-flight or just-finished upload.
    @ViewBuilder
    private var uploadBanner: some View {
        switch model.uploadPhase {
        case .idle:
            EmptyView()
        case .uploading(let name):
            banner {
                ProgressView().controlSize(.small)
                Text("Uploading \(name)…").foregroundStyle(.white)
            }
        case .succeeded(let name):
            banner {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Uploaded \(name).").foregroundStyle(.white)
                Spacer(minLength: 0)
                dismissButton
            }
        case .failed(let message):
            banner {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).foregroundStyle(.white)
                Spacer(minLength: 0)
                dismissButton
            }
        }
    }

    private func banner<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .font(.callout)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06))
    }

    private var dismissButton: some View {
        Button {
            model.dismissUploadBanner()
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private func shelfSection(_ shelf: HomeShelf) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(shelf.items) { item in
                    ItemCard(item: item) {
                        if item.deleteEntityId != nil {
                            Divider()
                            Button(role: .destructive) {
                                Task { await model.delete(item) }
                            } label: {
                                Label("Delete upload", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.and.arrow.up.on.square")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No uploads yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Upload your own audio files to play them anywhere you're signed in.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Upload music") { showingImporter = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(model.isUploading)
            Spacer()
        }
        .frame(maxWidth: 420, maxHeight: .infinity)
    }

    private var signedOutView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Your uploads live here")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Sign in to upload your own music and play it from any device.")
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
    UploadsView()
        .environment(PlayerState())
        .environment(AuthStore())
        .environment(Navigator())
        .environment(PlaylistCoordinator())
        .frame(width: 900, height: 600)
}
