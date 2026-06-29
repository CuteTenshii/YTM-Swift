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

    /// Increments on every sign-in / sign-out, so views can `.task(id:)` reload.
    private(set) var generation = 0

    var isSignedIn: Bool { state == .signedIn }

    init() {
        Task { await refresh() }
    }

    func refresh() async {
        if await CredentialStore.shared.isSignedIn {
            state = .signedIn
            await loadAccountInfo()
        } else {
            state = .signedOut
            account = nil
        }
    }

    /// Called by the login web view once it has captured a usable cookie jar.
    func completeLogin(with cookies: [HTTPCookie]) async {
        let credentials = Credentials(httpCookies: cookies)
        guard credentials.isUsable else { return }

        await CredentialStore.shared.update(credentials)
        state = .signedIn
        isPresentingLogin = false
        generation += 1
        await loadAccountInfo()
    }

    func signOut() async {
        await CredentialStore.shared.clear()
        await Self.clearWebData()
        state = .signedOut
        account = nil
        generation += 1
    }

    /// Best-effort: a failure here shouldn't change the signed-in state.
    private func loadAccountInfo() async {
        if let info = try? await InnerTubeClient.shared.accountInfo() {
            account = info
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
