//
//  LastfmPlugin.swift
//  YT Music
//
//

import SwiftUI
import AppKit

@MainActor
@Observable
final class LastfmPlugin: Plugin {
    let id = "lastfm-scrobbler"
    let name = "Last.fm Scrobbling"
    let summary = String(localized: "plugins.lastfm.summary")

    private let client = LastfmClient()
    private var tracker = ScrobbleTracker()
    private var active = false

    var session: LastfmSession?
    var awaitingAuthorization = false
    var working = false
    var statusMessage: String?

    init() {
        session = LastfmClient.loadSession()
    }

    func setActive(_ active: Bool) {
        self.active = active
        // Reset the tracker so toggling mid-track doesn't scrobble a partial play.
        if !active { tracker = ScrobbleTracker() }
    }

    func playbackDidChange(_ snapshot: PlaybackSnapshot?) {
        // Always advance the tracker; only dispatch network actions while enabled and connected.
        let actions = tracker.update(snapshot, now: Date())
        guard active, session != nil else { return }
        for action in actions {
            switch action {
            case .nowPlaying(let track):
                Task { await client.updateNowPlaying(track) }
            case .scrobble(let track):
                Task { await client.scrobble(track) }
            }
        }
    }

    // MARK: - Auth flow (driven by the config UI)

    /// Step 1: request a token and open the browser to approve it.
    func beginAuthorization(apiKey: String, secret: String) {
        statusMessage = nil
        working = true
        Task {
            defer { working = false }
            do {
                let token = try await client.requestToken(apiKey: apiKey, secret: secret)
                guard let url = client.authorizationURL(apiKey: apiKey, token: token) else {
                    statusMessage = String(localized: "plugins.lastfm.error.url")
                    return
                }
                NSWorkspace.shared.open(url)
                pendingToken = token
                awaitingAuthorization = true
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    /// Step 2: exchange the approved token for a session key.
    func completeAuthorization() {
        guard let token = pendingToken else { return }
        statusMessage = nil
        working = true
        Task {
            defer { working = false }
            do {
                session = try await client.completeAuthorization(token: token)
                awaitingAuthorization = false
                pendingToken = nil
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func disconnect() {
        session = nil
        awaitingAuthorization = false
        pendingToken = nil
        statusMessage = nil
        Task { await client.disconnect() }
    }

    private var pendingToken: String?

    var configuration: AnyView? { AnyView(LastfmConfigView(plugin: self)) }
}

private struct LastfmConfigView: View {
    @Bindable var plugin: LastfmPlugin

    @State private var apiKey = ""
    @State private var secret = ""

    private var canConnect: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
            && !secret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let session = plugin.session {
                HStack(spacing: 8) {
                    Text(String(format: String(localized: "plugins.lastfm.connected_as"), session.username))
                    Spacer()
                    Button("plugins.lastfm.disconnect", role: .destructive) { plugin.disconnect() }
                }
            } else if plugin.awaitingAuthorization {
                Text("plugins.lastfm.approve")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(plugin.working ? String(localized: "plugins.lastfm.finishing") : String(localized: "plugins.lastfm.finish")) {
                    plugin.completeAuthorization()
                }
                .disabled(plugin.working)
            } else {
                Text("plugins.lastfm.setup")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("plugins.lastfm.api_key", text: $apiKey)
                SecureField("plugins.lastfm.secret", text: $secret)
                Button(plugin.working ? String(localized: "plugins.lastfm.connecting") : String(localized: "plugins.lastfm.connect")) {
                    plugin.beginAuthorization(apiKey: apiKey, secret: secret)
                }
                .disabled(!canConnect || plugin.working)
            }

            if let message = plugin.statusMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}
