//
//  SongCreditsSheet.swift
//  YT Music
//

import SwiftUI

struct SongCreditsRequest: Identifiable {
    let id = UUID()
    var videoId: String
    var title: String
    var subtitle: String
    var thumbnailURL: URL?
}

struct SongCreditsSheet: View {
    let request: SongCreditsRequest
    let onFinish: () -> Void

    private enum LoadState {
        case loading
        case failed
        case loaded([CreditSection])
    }

    @State private var state = LoadState.loading

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 400, height: 460)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ArtworkView(url: request.thumbnailURL, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.title).font(.headline).lineLimit(1)
                Text(request.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
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
                    Text("Couldn't load credits.").foregroundStyle(.secondary)
                    Button("Try Again") { Task { await load() } }
                }
            }
        case .loaded(let sections) where sections.isEmpty:
            centered {
                Text("No credits available for this track.").foregroundStyle(.secondary)
            }
        case .loaded(let sections):
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sections, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.role)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(section.names, id: \.self) { name in
                                Text(name).textSelection(.enabled)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await InnerTubeClient.shared.credits(videoId: request.videoId))
        } catch {
            state = .failed
        }
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
