//
//  CredentialStore.swift
//  YT Music
//
//  Single source of truth for the signed-in session. Loads credentials from the
//  Keychain at launch, hands request headers to the networking layer, and
//  persists changes. Lives off the main actor so InnerTubeClient can await it.
//

import Foundation

actor CredentialStore {
    static let shared = CredentialStore()

    private let service = "moe.tenshii.YT-Music"
    private let account = "youtube-credentials"

    private(set) var credentials: Credentials?

    init() {
        if let data = Keychain.get(service: service, account: account),
           let stored = try? JSONDecoder().decode(Credentials.self, from: data) {
            credentials = stored
        }
    }

    var isSignedIn: Bool { credentials?.isUsable ?? false }

    /// Headers to merge into an authenticated request (empty when signed out).
    func requestHeaders() -> [String: String] {
        credentials?.requestHeaders(now: Date()) ?? [:]
    }

    func update(_ credentials: Credentials) {
        self.credentials = credentials
        if let data = try? JSONEncoder().encode(credentials) {
            Keychain.set(data, service: service, account: account)
        }
        NotificationCenter.default.post(name: .ytmCredentialsChanged, object: nil)
    }

    func clear() {
        credentials = nil
        Keychain.delete(service: service, account: account)
        NotificationCenter.default.post(name: .ytmCredentialsChanged, object: nil)
    }
}
