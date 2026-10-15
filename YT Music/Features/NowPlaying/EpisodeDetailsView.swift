//
//  EpisodeDetailsView.swift
//  YT Music
//
//  The inspector's Details page for a podcast episode: title, show, description.
//

import SwiftUI

@MainActor
@Observable
final class EpisodeDetailsViewModel {
    enum State {
        case loading
        case loaded(EpisodeDetails)
        case unavailable
    }

    private(set) var state: State = .loading
    private let client: InnerTubeClient

    init(client: InnerTubeClient = .shared) {
        self.client = client
    }

    func load(videoId: String?) async {
        guard let videoId else { state = .unavailable; return }
        state = .loading
        let details = try? await client.episodeDetails(videoId: videoId)
        guard !Task.isCancelled else { return }
        state = details.map { .loaded($0) } ?? .unavailable
    }
}

struct EpisodeDetailsView: View {
    let videoId: String?
    let navigate: (EntityDestination) -> Void
    @State private var model = EpisodeDetailsViewModel()

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            case .loaded(let details):
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(details.title)
                            .font(.headline)
                        if let show = details.show {
                            EntityLinkButton(link: show, font: .subheadline) { navigate(show.destination) }
                        } else if !details.showName.isEmpty {
                            Text(details.showName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(details.description)
                            .font(.callout)
                            .textSelection(.enabled)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            case .unavailable:
                ContentUnavailableView("No details", systemImage: "info.circle",
                                       description: Text("This episode has no description."))
                    .padding(.vertical, 32)
            }
        }
        .task(id: videoId) { await model.load(videoId: videoId) }
    }
}
