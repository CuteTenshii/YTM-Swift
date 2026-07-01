//
//  LastfmPlugin.swift
//  YT Music
//
//  Scrobbles played tracks to Last.fm while enabled. Feeds the PlaybackSnapshot
//  stream through a `ScrobbleTracker`, which decides when to send `nowPlaying`
//  and `scrobble`; the configuration UI takes the user's API account, runs the
//  desktop auth flow (approve in the browser), and shows the connected account.
//

import SwiftUI
import AppKit

@MainActor
@Observable
final class LastfmPlugin: Plugin {
    let id = "lastfm-scrobbler"
    let name = "Last.fm Scrobbling"
    let summary = "Scrobble the music you play to your Last.fm profile."

    private let client = LastfmClient()
    private var tracker = ScrobbleTracker()
    private var active = false

    /// The connected account, or nil when signed out. Drives the config UI.
    var session: LastfmSession?
    /// True once the auth flow has opened the browser and is awaiting completion.
    var awaitingAuthorization = false
    /// True while an auth request is in flight (disables the buttons).
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
        // Always advance the tracker so its time accounting stays correct, but
        // only dispatch network actions while enabled and connected.
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

    /// Step 1: get a token for the user's API account and open the browser to
    /// approve it. The password is never entered here — it's typed on last.fm.
    func beginAuthorization(apiKey: String, secret: String) {
        statusMessage = nil
        working = true
        Task {
            defer { working = false }
            do {
                let token = try await client.requestToken(apiKey: apiKey, secret: secret)
                guard let url = client.authorizationURL(apiKey: apiKey, token: token) else {
                    statusMessage = "Couldn't build the authorization URL."
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

/// Connect / disconnect controls shown under the toggle.
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
                    Text("Connected as ") + Text(session.username).bold()
                    Spacer()
                    Button("Disconnect", role: .destructive) { plugin.disconnect() }
                }
            } else if plugin.awaitingAuthorization {
                Text("Approve YT Music in the browser tab that just opened, then finish here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(plugin.working ? "Finishing…" : "I've approved — finish connecting") {
                    plugin.completeAuthorization()
                }
                .disabled(plugin.working)
            } else {
                Text("Create an API account at last.fm/api, then connect. You'll approve access in the browser — your password is never entered here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("API key", text: $apiKey)
                SecureField("Shared secret", text: $secret)
                Button(plugin.working ? "Connecting…" : "Connect to Last.fm") {
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
