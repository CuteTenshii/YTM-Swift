//
//  LastfmPlugin.swift
//  YT Music
//
//  Scrobbles played tracks to Last.fm while enabled. Feeds the PlaybackSnapshot
//  stream through a `ScrobbleTracker`, which decides when to send `nowPlaying`
//  and `scrobble`; the configuration UI runs the desktop auth flow (connect via
//  the browser) and shows the connected account.
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

    /// Step 1: get a token and open the browser for the user to authorize it.
    func beginAuthorization() {
        statusMessage = nil
        Task {
            do {
                let token = try await client.requestToken()
                guard let url = client.authorizationURL(token: token) else {
                    statusMessage = "Couldn't build the authorization URL."
                    return
                }
                NSWorkspace.shared.open(url)
                awaitingAuthorization = true
                pendingToken = token
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    /// Step 2: exchange the authorized token for a session key.
    func completeAuthorization() {
        guard let token = pendingToken else { return }
        Task {
            do {
                session = try await client.completeAuthorization(token: token)
                awaitingAuthorization = false
                pendingToken = nil
                statusMessage = nil
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let session = plugin.session {
                LabeledContent("Connected as") {
                    HStack(spacing: 8) {
                        Text(session.username).foregroundStyle(.secondary)
                        Button("Disconnect", role: .destructive) { plugin.disconnect() }
                    }
                }
            } else if plugin.awaitingAuthorization {
                Text("Authorize YT Music in the browser tab that just opened, then finish here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("I've authorized — finish connecting") { plugin.completeAuthorization() }
            } else {
                Button("Connect to Last.fm") { plugin.beginAuthorization() }
            }

            if let message = plugin.statusMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
