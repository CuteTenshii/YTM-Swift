//
//  AuthStore.swift
//  YT Music
//
//  Observable sign-in state; bumps `generation` on auth changes.
//

import SwiftUI
import WebKit

@MainActor
@Observable
final class AuthStore {
    enum State {
        case unknown
        case signedOut
        case signedIn
    }

    private(set) var state: State = .unknown
    private(set) var account: AccountInfo?
    var isPresentingLogin = false

    /// Set on a 401: stored cookies are stale; drives the re-sign-in banner.
    private(set) var sessionExpired = false

    private(set) var generation = 0

    var isSignedIn: Bool { state == .signedIn }

    private let defaults: UserDefaults
    private static let accountKey = "auth.account"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.accountKey),
           let cached = try? JSONDecoder().decode(AccountInfo.self, from: data) {
            account = cached
            state = .signedIn
        }
        // A 401 on an authenticated request (posted by InnerTubeClient) means the session expired.
        NotificationCenter.default.addObserver(
            forName: .ytmSessionExpired, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteSessionExpired() }
        }
        Task { await refresh() }
    }

    private func noteSessionExpired() {
        guard state == .signedIn else { return }
        sessionExpired = true
    }

    func dismissExpiredNotice() {
        sessionExpired = false
    }

    func refresh() async {
        let wasSignedIn = isSignedIn
        if await CredentialStore.shared.isSignedIn {
            state = .signedIn
        } else {
            state = .signedOut
            setAccount(nil)
        }
        if isSignedIn != wasSignedIn { generation += 1 }
        if isSignedIn { await loadAccountInfo() }
    }

    func completeLogin(with cookies: [HTTPCookie]) async {
        let credentials = Credentials(httpCookies: cookies)
        guard credentials.isUsable else { return }

        await CredentialStore.shared.update(credentials)
        state = .signedIn
        sessionExpired = false
        isPresentingLogin = false
        generation += 1
        await loadAccountInfo()
    }

    func signOut() async {
        await CredentialStore.shared.clear()
        await Self.clearWebData()
        state = .signedOut
        setAccount(nil)
        sessionExpired = false
        generation += 1
    }

    private func loadAccountInfo() async {
        if let info = try? await InnerTubeClient.shared.accountInfo() {
            setAccount(info)
        }
    }

    private func setAccount(_ info: AccountInfo?) {
        account = info
        if let info, let data = try? JSONEncoder().encode(info) {
            defaults.set(data, forKey: Self.accountKey)
        } else {
            defaults.removeObject(forKey: Self.accountKey)
        }
    }

    private static func clearWebData() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records)
    }
}
