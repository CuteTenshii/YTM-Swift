//
//  AuthStore.swift
//  YT Music
//
//  Observable, app-wide sign-in state. Bridges the (off-main) CredentialStore to
//  the UI and bumps `generation` whenever auth changes so screens can reload
//  their now-personalized content.
//

import SwiftUI
import WebKit

@MainActor
@Observable
final class AuthStore {
    enum State {
        case unknown      // still loading from Keychain
        case signedOut
        case signedIn
    }

    private(set) var state: State = .unknown
    private(set) var account: AccountInfo?
    var isPresentingLogin = false

    /// True after an authenticated request came back 401: the stored cookies are
    /// stale and the user needs to sign in again. Drives the re-sign-in banner.
    private(set) var sessionExpired = false

    /// Increments on every sign-in / sign-out, so views can `.task(id:)` reload.
    private(set) var generation = 0

    var isSignedIn: Bool { state == .signedIn }

    private let defaults: UserDefaults
    private static let accountKey = "auth.account"

    /// Starts from the cached account, if any, so the UI and first loads are
    /// signed in without waiting on the Keychain.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.accountKey),
           let cached = try? JSONDecoder().decode(AccountInfo.self, from: data) {
            account = cached
            state = .signedIn
        }
        // A 401 on any authenticated request (posted by InnerTubeClient) means the
        // session expired; surface a banner prompting re-authentication.
        NotificationCenter.default.addObserver(
            forName: .ytmSessionExpired, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteSessionExpired() }
        }
        Task { await refresh() }
    }

    /// Marks the session expired (unless already signed out). Idempotent.
    private func noteSessionExpired() {
        guard state == .signedIn else { return }
        sessionExpired = true
    }

    /// Dismisses the expired banner without signing out (the user can retry later).
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

    /// Called by the login web view once it has captured a usable cookie jar.
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

    /// Best-effort: a failure here shouldn't change the signed-in state.
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

    /// Clears the login web view's persisted cookies so the next sign-in starts
    /// fresh (and the browser session doesn't linger after sign-out).
    private static func clearWebData() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records)
    }
}
