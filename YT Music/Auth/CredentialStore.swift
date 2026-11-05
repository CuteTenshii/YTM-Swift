//
//  CredentialStore.swift
//  YT Music
//
//  Keychain-backed source of truth for the session; off-main so InnerTubeClient can await it.
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
